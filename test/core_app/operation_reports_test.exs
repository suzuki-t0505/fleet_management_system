defmodule CoreApp.OperationReportsTest do
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.OperationReportsFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.AuditLogs.AuditLog
  alias CoreApp.OperationReports
  alias CoreApp.OperationReports.OperationReport
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Vehicles

  defp setup_context(_context) do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    manager_a = manager_fixture(%{office_id: office_a.id}) |> Scope.for_user()
    manager_b = manager_fixture(%{office_id: office_b.id}) |> Scope.for_user()
    admin = admin_fixture(%{office_id: office_a.id}) |> Scope.for_user()

    vehicle = vehicle_fixture(manager_a)
    driver = driver_fixture(manager_a)

    member_user = user_fixture(%{office_id: office_a.id})
    member_driver = driver_fixture(manager_a, %{"user_id" => member_user.id})
    member = %{Scope.for_user(member_user) | driver_id: member_driver.id}

    %{
      office_a: office_a,
      office_b: office_b,
      manager_a: manager_a,
      manager_b: manager_b,
      admin: admin,
      vehicle: vehicle,
      driver: driver,
      member: member,
      member_driver: member_driver,
      member_user: member_user
    }
  end

  describe "create_operation_report/2 の検証" do
    setup :setup_context

    test "必須項目があれば作成できる", %{manager_a: scope, vehicle: vehicle, driver: driver} do
      assert {:ok, %OperationReport{} = report} =
               OperationReports.create_operation_report(
                 scope,
                 valid_report_attributes(vehicle, driver)
               )

      assert report.status == :draft
      assert report.created_by_user_id == scope.user.id
    end

    test "V-12 走行距離は自動計算され、手入力値は無視される", %{
      manager_a: scope,
      vehicle: vehicle,
      driver: driver
    } do
      {:ok, report} =
        OperationReports.create_operation_report(
          scope,
          valid_report_attributes(vehicle, driver, %{
            "start_odometer" => "10000",
            "end_odometer" => "10250",
            "distance_km" => "99999"
          })
        )

      assert report.distance_km == 250
    end

    test "V-9 帰着日時が出発日時より前だと保存できない", %{
      manager_a: scope,
      vehicle: vehicle,
      driver: driver
    } do
      attrs = valid_report_attributes(vehicle, driver)
      reversed = %{attrs | "returned_at" => attrs["departed_at"]}

      assert {:error, changeset} = OperationReports.create_operation_report(scope, reversed)
      assert %{returned_at: ["は出発日時より後の日時を入力してください"]} = errors_on(changeset)
    end

    test "V-14 運行日に未来日は入力できない", %{manager_a: scope, vehicle: vehicle, driver: driver} do
      future = Date.add(ConvertDatetime.today(), 1)

      assert {:error, changeset} =
               OperationReports.create_operation_report(
                 scope,
                 valid_report_attributes(vehicle, driver, %{
                   "operation_date" => Date.to_iso8601(future)
                 })
               )

      assert "に未来の日付は入力できません" in errors_on(changeset).operation_date
    end

    test "追加1 運行日は出発日または帰着日と一致する必要がある", %{
      manager_a: scope,
      vehicle: vehicle,
      driver: driver
    } do
      other_day = Date.add(ConvertDatetime.today(), -5)

      assert {:error, changeset} =
               OperationReports.create_operation_report(
                 scope,
                 valid_report_attributes(vehicle, driver, %{
                   "operation_date" => Date.to_iso8601(other_day)
                 })
               )

      assert "は出発日または帰着日と同じ日付にしてください" in errors_on(changeset).operation_date
    end

    test "V-15 休憩時間は運行時間未満", %{manager_a: scope, vehicle: vehicle, driver: driver} do
      assert {:error, changeset} =
               OperationReports.create_operation_report(
                 scope,
                 valid_report_attributes(vehicle, driver, %{"rest_minutes" => "600"})
               )

      assert %{rest_minutes: ["は運行時間（480分）未満にしてください"]} = errors_on(changeset)
    end

    test "V-10 一般利用者はオドメーターの逆転を保存できない", %{
      member: scope,
      vehicle: vehicle,
      member_driver: driver
    } do
      attrs =
        valid_report_attributes(vehicle, driver, %{
          "start_odometer" => "10000",
          "end_odometer" => "9000"
        })

      assert {:error, changeset} = OperationReports.create_operation_report(scope, attrs)
      assert %{end_odometer: ["は出発時の走行距離計以上の値を入力してください"]} = errors_on(changeset)
    end

    test "V-10 運行管理者はオドメーターの逆転を保存できる（走行距離は0km）", %{
      manager_a: scope,
      vehicle: vehicle,
      driver: driver
    } do
      attrs =
        valid_report_attributes(vehicle, driver, %{
          "start_odometer" => "10000",
          "end_odometer" => "9000",
          "note" => "メーター交換のため"
        })

      assert {:ok, report} = OperationReports.create_operation_report(scope, attrs)
      assert report.distance_km == 0
    end
  end

  describe "フォーム入力の時刻変換" do
    setup :setup_context

    test "datetime-local の入力はJSTとして保存される", %{
      manager_a: scope,
      vehicle: vehicle,
      driver: driver
    } do
      today = ConvertDatetime.today()

      attrs =
        valid_report_attributes(vehicle, driver, %{
          "operation_date" => Date.to_iso8601(today),
          "departed_at" => "#{Date.to_iso8601(today)}T07:30",
          "returned_at" => "#{Date.to_iso8601(today)}T15:45"
        })

      {:ok, report} = OperationReports.create_operation_report(scope, attrs)

      # JST 07:30 は UTC 前日 22:30
      assert report.departed_at == DateTime.new!(Date.add(today, -1), ~T[22:30:00])
      # 表示に戻すと入力値と一致する
      assert ConvertDatetime.to_input_value(report.departed_at) ==
               "#{Date.to_iso8601(today)}T07:30"
    end

    test "給油日時もJSTとして保存される", %{manager_a: scope, vehicle: vehicle, driver: driver} do
      today = ConvertDatetime.today()

      attrs =
        valid_report_attributes(vehicle, driver, %{
          "operation_date" => Date.to_iso8601(today),
          "departed_at" => "#{Date.to_iso8601(today)}T07:00",
          "returned_at" => "#{Date.to_iso8601(today)}T18:00",
          "refuelings" => %{
            "0" => %{"refueled_at" => "#{Date.to_iso8601(today)}T12:00", "liters" => "30"}
          }
        })

      {:ok, report} = OperationReports.create_operation_report(scope, attrs)
      [refueling] = Repo.preload(report, :refuelings).refuelings

      assert ConvertDatetime.to_input_value(refueling.refueled_at) ==
               "#{Date.to_iso8601(today)}T12:00"
    end
  end

  describe "日報の拠点" do
    setup :setup_context

    test "車両の配置拠点が日報の拠点になる", %{
      admin: admin,
      manager_a: manager,
      vehicle: vehicle,
      driver: driver,
      office_a: office_a
    } do
      # 管理者（拠点はA営業所だが全拠点を扱う）がA営業所の車両で作成する
      {:ok, report} =
        OperationReports.create_operation_report(
          admin,
          valid_report_attributes(vehicle, driver)
        )

      assert report.office_id == office_a.id
      assert OperationReports.get_operation_report!(manager, report.id).id == report.id
    end

    test "管理者は他拠点の車両でも日報を作成でき、その拠点の日報になる", %{
      admin: admin,
      manager_b: manager_b,
      office_b: office_b
    } do
      other_vehicle = vehicle_fixture(manager_b)
      other_driver = driver_fixture(manager_b)

      {:ok, report} =
        OperationReports.create_operation_report(
          admin,
          valid_report_attributes(other_vehicle, other_driver)
        )

      assert report.office_id == office_b.id
      assert OperationReports.get_operation_report!(manager_b, report.id).id == report.id
    end

    test "運行管理者は他拠点の車両を指定できない", %{manager_a: manager_a, manager_b: manager_b} do
      other_vehicle = vehicle_fixture(manager_b)
      other_driver = driver_fixture(manager_b)

      assert {:error, changeset} =
               OperationReports.create_operation_report(
                 manager_a,
                 valid_report_attributes(other_vehicle, other_driver)
               )

      assert %{vehicle_id: ["は自拠点の車両を選択してください"]} = errors_on(changeset)
    end
  end

  describe "給油記録" do
    setup :setup_context

    test "日報と同時に保存できる", %{manager_a: scope, vehicle: vehicle, driver: driver} do
      attrs = valid_report_attributes(vehicle, driver)

      refueled_at =
        attrs["departed_at"] |> DateTime.from_iso8601() |> elem(1) |> DateTime.add(2, :hour)

      attrs =
        Map.put(attrs, "refuelings", %{
          "0" => %{
            "refueled_at" => DateTime.to_iso8601(refueled_at),
            "liters" => "45.5",
            "amount_yen" => "7280",
            "odometer" => "10050"
          }
        })

      assert {:ok, report} = OperationReports.create_operation_report(scope, attrs)
      assert [refueling] = Repo.preload(report, :refuelings).refuelings
      assert Decimal.equal?(refueling.liters, Decimal.new("45.5"))
    end

    test "V-16 給油量が0以下だと日報ごと保存されない（V-17）", %{
      manager_a: scope,
      vehicle: vehicle,
      driver: driver
    } do
      attrs = valid_report_attributes(vehicle, driver)

      refueled_at =
        attrs["departed_at"] |> DateTime.from_iso8601() |> elem(1) |> DateTime.add(2, :hour)

      attrs =
        Map.put(attrs, "refuelings", %{
          "0" => %{"refueled_at" => DateTime.to_iso8601(refueled_at), "liters" => "0"}
        })

      assert {:error, _changeset} = OperationReports.create_operation_report(scope, attrs)
      assert Repo.all(OperationReport) == []
    end

    test "追加2 給油日時が運行時間外だと保存できない", %{
      manager_a: scope,
      vehicle: vehicle,
      driver: driver
    } do
      attrs = valid_report_attributes(vehicle, driver)

      outside =
        attrs["departed_at"] |> DateTime.from_iso8601() |> elem(1) |> DateTime.add(-2, :hour)

      attrs =
        Map.put(attrs, "refuelings", %{
          "0" => %{"refueled_at" => DateTime.to_iso8601(outside), "liters" => "30"}
        })

      assert {:error, changeset} = OperationReports.create_operation_report(scope, attrs)
      assert [refueling_changeset] = changeset.changes.refuelings
      assert %{refueled_at: ["は出発日時より後にしてください"]} = errors_on(refueling_changeset)
    end
  end

  describe "warnings/2" do
    setup :setup_context

    test "V-11 前回の帰着時オドメーターを下回ると警告する", %{
      manager_a: scope,
      vehicle: vehicle,
      driver: driver
    } do
      report_fixture(scope, vehicle, driver, %{
        "start_odometer" => "10000",
        "end_odometer" => "10500"
      })

      today = ConvertDatetime.today()
      departed_at = DateTime.new!(today, ~T[02:00:00])

      changeset =
        OperationReports.change_operation_report(
          %OperationReport{},
          scope,
          valid_report_attributes(vehicle, driver, %{
            "departed_at" => DateTime.to_iso8601(departed_at),
            "returned_at" => DateTime.to_iso8601(DateTime.add(departed_at, 4, :hour)),
            "start_odometer" => "10200",
            "end_odometer" => "10300"
          })
        )

      assert [warning] = OperationReports.warnings(scope, changeset)
      assert warning =~ "10500 km を下回っています"
    end

    test "V-13 同一車両で時間帯が重なると警告する", %{
      manager_a: scope,
      vehicle: vehicle,
      driver: driver
    } do
      existing = report_fixture(scope, vehicle, driver)

      changeset =
        OperationReports.change_operation_report(
          %OperationReport{},
          scope,
          valid_report_attributes(vehicle, driver, %{
            "departed_at" => DateTime.to_iso8601(existing.departed_at),
            "returned_at" => DateTime.to_iso8601(existing.returned_at),
            "start_odometer" => "20000",
            "end_odometer" => "20100"
          })
        )

      assert Enum.any?(OperationReports.warnings(scope, changeset), &(&1 =~ "時間帯が重なる日報"))
    end

    test "問題がなければ警告は返らない", %{manager_a: scope, vehicle: vehicle, driver: driver} do
      changeset =
        OperationReports.change_operation_report(
          %OperationReport{},
          scope,
          valid_report_attributes(vehicle, driver)
        )

      assert OperationReports.warnings(scope, changeset) == []
    end
  end

  describe "スコープ境界" do
    setup :setup_context

    test "一般利用者は自分が運転者の日報のみ参照できる", %{
      member: member,
      manager_a: manager,
      vehicle: vehicle,
      driver: driver,
      member_driver: member_driver
    } do
      mine = report_fixture(manager, vehicle, member_driver)
      others = report_fixture(manager, vehicle, driver)

      assert [found] = OperationReports.list_operation_reports(member).entries
      assert found.id == mine.id

      assert_raise Ecto.NoResultsError, fn ->
        OperationReports.get_operation_report!(member, others.id)
      end
    end

    test "運転者が紐付いていない一般利用者は1件も参照できない", %{
      manager_a: manager,
      vehicle: vehicle,
      driver: driver,
      office_a: office
    } do
      report_fixture(manager, vehicle, driver)
      unlinked = user_fixture(%{office_id: office.id}) |> Scope.for_user()

      assert OperationReports.list_operation_reports(unlinked).total_entries == 0
    end

    test "運行管理者は他拠点の日報を参照できない", %{
      manager_a: manager_a,
      manager_b: manager_b,
      vehicle: vehicle,
      driver: driver
    } do
      report = report_fixture(manager_a, vehicle, driver)

      assert_raise Ecto.NoResultsError, fn ->
        OperationReports.get_operation_report!(manager_b, report.id)
      end

      assert OperationReports.list_operation_reports(manager_b).total_entries == 0
    end

    test "管理者は全拠点の日報を参照できる", %{
      admin: admin,
      manager_a: manager,
      vehicle: vehicle,
      driver: driver
    } do
      report = report_fixture(manager, vehicle, driver)

      assert OperationReports.get_operation_report!(admin, report.id).id == report.id
    end
  end

  describe "list_operation_reports/2 の絞り込み" do
    setup :setup_context

    test "既定は当月の日報を返す", %{manager_a: scope, vehicle: vehicle, driver: driver} do
      report_fixture(scope, vehicle, driver)

      assert OperationReports.list_operation_reports(scope).total_entries == 1
    end

    test "期間で絞り込める", %{manager_a: scope, vehicle: vehicle, driver: driver} do
      report_fixture(scope, vehicle, driver)
      past = Date.add(ConvertDatetime.today(), -90)

      assert OperationReports.list_operation_reports(scope, %{
               "from" => Date.to_iso8601(Date.add(past, -1)),
               "to" => Date.to_iso8601(past)
             }).total_entries == 0
    end

    test "ステータスで絞り込める", %{manager_a: scope, vehicle: vehicle, driver: driver} do
      report_fixture(scope, vehicle, driver)

      submitted =
        submitted_report_fixture(scope, vehicle, driver, %{
          "start_odometer" => "20000",
          "end_odometer" => "20100"
        })

      assert [found] =
               OperationReports.list_operation_reports(scope, %{"status" => "submitted"}).entries

      assert found.id == submitted.id
    end

    test "車両で絞り込める", %{manager_a: scope, vehicle: vehicle, driver: driver} do
      report = report_fixture(scope, vehicle, driver)
      other_vehicle = vehicle_fixture(scope)

      report_fixture(scope, other_vehicle, driver, %{
        "start_odometer" => "500",
        "end_odometer" => "600"
      })

      assert [found] =
               OperationReports.list_operation_reports(scope, %{"vehicle_id" => vehicle.id}).entries

      assert found.id == report.id
    end
  end

  describe "状態遷移" do
    setup :setup_context

    test "下書きを提出できる", %{member: scope, vehicle: vehicle, member_driver: driver} do
      report = report_fixture(scope, vehicle, driver)

      assert {:ok, submitted} = OperationReports.submit_report(scope, report)
      assert submitted.status == :submitted
      assert submitted.submitted_at
    end

    test "提出済みの日報は再提出できない", %{member: scope, vehicle: vehicle, member_driver: driver} do
      report = submitted_report_fixture(scope, vehicle, driver)

      assert {:error, :invalid_status} = OperationReports.submit_report(scope, report)
    end

    test "他人の日報は提出できない", %{
      member: member,
      manager_a: manager,
      vehicle: vehicle,
      driver: driver
    } do
      report = report_fixture(manager, vehicle, driver)

      assert {:error, :unauthorized} = OperationReports.submit_report(member, report)
    end

    test "運行管理者は提出済みの日報を承認できる", %{
      manager_a: manager,
      member: member,
      vehicle: vehicle,
      member_driver: driver
    } do
      report = submitted_report_fixture(member, vehicle, driver)

      assert {:ok, approved} = OperationReports.approve_report(manager, report)
      assert approved.status == :approved
      assert approved.approved_by_user_id == manager.user.id
      assert approved.approved_at
    end

    test "V-18 承認で車両の最終オドメーターが更新される", %{
      manager_a: manager,
      member: member,
      vehicle: vehicle,
      member_driver: driver
    } do
      report =
        submitted_report_fixture(member, vehicle, driver, %{
          "start_odometer" => "10000",
          "end_odometer" => "10400"
        })

      {:ok, _approved} = OperationReports.approve_report(manager, report)

      assert Vehicles.get_vehicle!(manager, vehicle.id).latest_odometer == 10_400
    end

    test "V-18 現在値より小さい場合は更新しない", %{
      manager_a: manager,
      member: member,
      vehicle: vehicle,
      member_driver: driver
    } do
      {:ok, vehicle} = Vehicles.update_vehicle(manager, vehicle, %{"note" => "初期化"})

      first =
        submitted_report_fixture(member, vehicle, driver, %{
          "start_odometer" => "30000",
          "end_odometer" => "30500"
        })

      {:ok, _} = OperationReports.approve_report(manager, first)

      today = ConvertDatetime.today()
      departed_at = DateTime.new!(today, ~T[03:00:00])

      second =
        submitted_report_fixture(member, vehicle, driver, %{
          "departed_at" => DateTime.to_iso8601(departed_at),
          "returned_at" => DateTime.to_iso8601(DateTime.add(departed_at, 2, :hour)),
          "start_odometer" => "20000",
          "end_odometer" => "20100"
        })

      {:ok, _} = OperationReports.approve_report(manager, second)

      assert Vehicles.get_vehicle!(manager, vehicle.id).latest_odometer == 30_500
    end

    test "承認で監査ログが記録される", %{
      manager_a: manager,
      member: member,
      vehicle: vehicle,
      member_driver: driver
    } do
      report = submitted_report_fixture(member, vehicle, driver)
      Repo.delete_all(AuditLog)

      {:ok, _} = OperationReports.approve_report(manager, report)

      assert [log] = Repo.all(AuditLog)
      assert log.action == :approve
      assert log.resource_type == "operation_report"
    end

    test "一般利用者は承認できない", %{member: member, vehicle: vehicle, member_driver: driver} do
      report = submitted_report_fixture(member, vehicle, driver)

      assert {:error, :unauthorized} = OperationReports.approve_report(member, report)
    end

    test "V-19 差戻しには理由が必要", %{
      manager_a: manager,
      member: member,
      vehicle: vehicle,
      member_driver: driver
    } do
      report = submitted_report_fixture(member, vehicle, driver)

      assert {:error, changeset} = OperationReports.reject_report(manager, report, "")
      assert %{rejected_reason: ["差戻しの理由を入力してください"]} = errors_on(changeset)
    end

    test "差し戻すと運転者が編集・再提出できる", %{
      manager_a: manager,
      member: member,
      vehicle: vehicle,
      member_driver: driver
    } do
      report = submitted_report_fixture(member, vehicle, driver)

      assert {:ok, rejected} =
               OperationReports.reject_report(manager, report, "オドメーターを確認してください")

      assert rejected.status == :rejected
      assert rejected.rejected_reason == "オドメーターを確認してください"
      assert OperationReports.editable?(member, rejected)

      assert {:ok, resubmitted} = OperationReports.submit_report(member, rejected)
      assert resubmitted.status == :submitted
      assert is_nil(resubmitted.rejected_reason)
    end

    test "承認済みの日報は差し戻せない", %{
      manager_a: manager,
      member: member,
      vehicle: vehicle,
      member_driver: driver
    } do
      report = submitted_report_fixture(member, vehicle, driver)
      {:ok, approved} = OperationReports.approve_report(manager, report)

      assert {:error, :invalid_status} = OperationReports.reject_report(manager, approved, "理由")
    end
  end

  describe "editable?/2" do
    setup :setup_context

    test "運転者は下書きと差戻しのみ編集できる", %{
      member: member,
      manager_a: manager,
      vehicle: vehicle,
      member_driver: driver
    } do
      draft = report_fixture(member, vehicle, driver)
      assert OperationReports.editable?(member, draft)

      {:ok, submitted} = OperationReports.submit_report(member, draft)
      refute OperationReports.editable?(member, submitted)

      {:ok, rejected} = OperationReports.reject_report(manager, submitted, "確認してください")
      assert OperationReports.editable?(member, rejected)
    end

    test "運行管理者は承認済み以外を編集できる", %{
      manager_a: manager,
      member: member,
      vehicle: vehicle,
      member_driver: driver
    } do
      report = submitted_report_fixture(member, vehicle, driver)
      assert OperationReports.editable?(manager, report)

      {:ok, approved} = OperationReports.approve_report(manager, report)
      refute OperationReports.editable?(manager, approved)
    end

    test "管理者は承認済みも編集できる", %{
      admin: admin,
      manager_a: manager,
      member: member,
      vehicle: vehicle,
      member_driver: driver
    } do
      report = submitted_report_fixture(member, vehicle, driver)
      {:ok, approved} = OperationReports.approve_report(manager, report)

      assert OperationReports.editable?(admin, approved)
    end
  end

  describe "delete_operation_report/2" do
    setup :setup_context

    test "下書きは削除できる", %{member: scope, vehicle: vehicle, member_driver: driver} do
      report = report_fixture(scope, vehicle, driver)

      assert {:ok, _} = OperationReports.delete_operation_report(scope, report)
      assert Repo.all(OperationReport) == []
    end

    test "提出済みは削除できない", %{member: scope, vehicle: vehicle, member_driver: driver} do
      report = submitted_report_fixture(scope, vehicle, driver)

      assert {:error, :not_draft} = OperationReports.delete_operation_report(scope, report)
    end
  end
end
