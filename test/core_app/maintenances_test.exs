defmodule CoreApp.MaintenancesTest do
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.DriversFixtures
  import CoreApp.MaintenancesFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.OperationReportsFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.AuditLogs.AuditLog
  alias CoreApp.Maintenances
  alias CoreApp.Maintenances.Maintenance
  alias CoreApp.OperationReports
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Vehicles

  defp setup_offices(_context) do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    manager_a = manager_fixture(%{office_id: office_a.id}) |> Scope.for_user()
    manager_b = manager_fixture(%{office_id: office_b.id}) |> Scope.for_user()
    admin = admin_fixture(%{office_id: office_a.id}) |> Scope.for_user()

    %{
      office_a: office_a,
      office_b: office_b,
      manager_a: manager_a,
      manager_b: manager_b,
      admin: admin,
      vehicle_a: vehicle_fixture(manager_a),
      vehicle_b: vehicle_fixture(manager_b)
    }
  end

  describe "create_maintenance/3" do
    setup :setup_offices

    test "必須項目があれば登録できる", %{manager_a: scope, office_a: office, vehicle_a: vehicle} do
      assert {:ok, %Maintenance{} = maintenance} =
               Maintenances.create_maintenance(scope, valid_maintenance_attributes(vehicle))

      assert maintenance.office_id == office.id
      assert maintenance.created_by_user_id == scope.user.id
      assert String.length(maintenance.id) == 26
    end

    test "V-20 車検は新しい車検満了日が必須", %{manager_a: scope, vehicle_a: vehicle} do
      attrs = valid_maintenance_attributes(vehicle, %{"category" => "inspection"})

      assert {:error, changeset} = Maintenances.create_maintenance(scope, attrs)
      assert errors_on(changeset).next_scheduled_on == ["（新しい車検満了日）を入力してください"]
    end

    test "V-20 車検を登録すると車両の車検満了日が更新される", %{manager_a: scope, vehicle_a: vehicle} do
      next = Date.add(ConvertDatetime.today(), 730)

      {:ok, _maintenance} =
        Maintenances.create_maintenance(
          scope,
          valid_maintenance_attributes(vehicle, %{
            "category" => "inspection",
            "next_scheduled_on" => Date.to_iso8601(next)
          })
        )

      assert Vehicles.get_vehicle!(scope, vehicle.id).inspection_expires_on == next
    end

    test "V-21 法定点検は次回予定日が必須", %{manager_a: scope, vehicle_a: vehicle} do
      attrs = valid_maintenance_attributes(vehicle, %{"category" => "periodic_3m"})

      assert {:error, changeset} = Maintenances.create_maintenance(scope, attrs)
      assert errors_on(changeset).next_scheduled_on == ["（次回の点検予定日）を入力してください"]
    end

    test "V-21 3ヶ月点検・12ヶ月点検はそれぞれの予定日を更新する", %{manager_a: scope, vehicle_a: vehicle} do
      next_3m = Date.add(ConvertDatetime.today(), 90)
      next_12m = Date.add(ConvertDatetime.today(), 365)

      {:ok, _} =
        Maintenances.create_maintenance(
          scope,
          valid_maintenance_attributes(vehicle, %{
            "category" => "periodic_3m",
            "next_scheduled_on" => Date.to_iso8601(next_3m)
          })
        )

      {:ok, _} =
        Maintenances.create_maintenance(
          scope,
          valid_maintenance_attributes(vehicle, %{
            "category" => "periodic_12m",
            "next_scheduled_on" => Date.to_iso8601(next_12m)
          })
        )

      updated = Vehicles.get_vehicle!(scope, vehicle.id)

      assert updated.next_periodic_3m_on == next_3m
      assert updated.next_periodic_12m_on == next_12m
    end

    test "期限に対応しない区分は車両を更新しない", %{manager_a: scope, vehicle_a: vehicle} do
      {:ok, _} =
        Maintenances.create_maintenance(
          scope,
          valid_maintenance_attributes(vehicle, %{
            "category" => "oil",
            "next_scheduled_on" => Date.to_iso8601(Date.add(ConvertDatetime.today(), 180))
          })
        )

      updated = Vehicles.get_vehicle!(scope, vehicle.id)

      assert updated.inspection_expires_on == vehicle.inspection_expires_on
      assert updated.next_periodic_3m_on == vehicle.next_periodic_3m_on
    end

    test "V-22 実施日に未来日は登録できない", %{manager_a: scope, vehicle_a: vehicle} do
      tomorrow = ConvertDatetime.today() |> Date.add(1) |> Date.to_iso8601()
      attrs = valid_maintenance_attributes(vehicle, %{"performed_on" => tomorrow})

      assert {:error, changeset} = Maintenances.create_maintenance(scope, attrs)
      assert errors_on(changeset).performed_on == ["に未来の日付は入力できません"]
    end

    test "次回予定日は実施日以降でなければならない", %{manager_a: scope, vehicle_a: vehicle} do
      yesterday = ConvertDatetime.today() |> Date.add(-1) |> Date.to_iso8601()

      attrs =
        valid_maintenance_attributes(vehicle, %{
          "category" => "inspection",
          "next_scheduled_on" => yesterday
        })

      assert {:error, changeset} = Maintenances.create_maintenance(scope, attrs)
      assert errors_on(changeset).next_scheduled_on == ["は実施日以降の日付を入力してください"]
    end

    test "運行管理者は他拠点の車両を選べない", %{manager_a: scope, vehicle_b: vehicle_b} do
      assert {:error, changeset} =
               Maintenances.create_maintenance(scope, valid_maintenance_attributes(vehicle_b))

      assert errors_on(changeset).vehicle_id == ["は自拠点の車両を選択してください"]
    end

    test "管理者が代理登録しても車両の拠点の記録になる", %{admin: scope, office_b: office_b, vehicle_b: vehicle_b} do
      {:ok, maintenance} =
        Maintenances.create_maintenance(scope, valid_maintenance_attributes(vehicle_b))

      assert maintenance.office_id == office_b.id
    end

    test "監査ログを記録する", %{manager_a: scope, vehicle_a: vehicle} do
      Repo.delete_all(AuditLog)

      {:ok, maintenance} =
        Maintenances.create_maintenance(scope, valid_maintenance_attributes(vehicle))

      assert [log] = Repo.all(AuditLog)
      assert log.action == :create
      assert log.resource_type == "maintenance"
      assert log.resource_id == maintenance.id
      assert log.user_id == scope.user.id
    end

    test "保存に失敗した場合は車両も監査ログも変わらない", %{manager_a: scope, vehicle_a: vehicle} do
      attrs = valid_maintenance_attributes(vehicle, %{"category" => "inspection"})
      Repo.delete_all(AuditLog)

      assert {:error, _changeset} = Maintenances.create_maintenance(scope, attrs)
      assert Repo.all(AuditLog) == []
      assert Repo.all(Maintenance) == []

      assert Vehicles.get_vehicle!(scope, vehicle.id).inspection_expires_on ==
               vehicle.inspection_expires_on
    end
  end

  describe "update_maintenance/4" do
    setup :setup_offices

    test "更新すると車両の期限も更新される", %{manager_a: scope, vehicle_a: vehicle} do
      next = Date.add(ConvertDatetime.today(), 700)

      maintenance =
        maintenance_fixture(scope, vehicle, %{
          "category" => "inspection",
          "next_scheduled_on" => Date.to_iso8601(Date.add(ConvertDatetime.today(), 365))
        })

      {:ok, _updated} =
        Maintenances.update_maintenance(scope, maintenance, %{
          "next_scheduled_on" => Date.to_iso8601(next)
        })

      assert Vehicles.get_vehicle!(scope, vehicle.id).inspection_expires_on == next
    end

    test "監査ログに差分を記録する", %{manager_a: scope, vehicle_a: vehicle} do
      maintenance = maintenance_fixture(scope, vehicle)
      Repo.delete_all(AuditLog)

      {:ok, _updated} =
        Maintenances.update_maintenance(scope, maintenance, %{"vendor" => "別の工場"})

      assert [log] = Repo.all(AuditLog)
      assert log.action == :update
      assert log.changes == %{"vendor" => "別の工場"}
    end
  end

  describe "list_maintenances/2" do
    setup :setup_offices

    test "自拠点の記録のみを実施日の降順で返す", %{
      manager_a: scope,
      manager_b: other,
      vehicle_a: vehicle_a,
      vehicle_b: vehicle_b
    } do
      old = maintenance_fixture(scope, vehicle_a, %{"performed_on" => "2026-01-10"})
      new = maintenance_fixture(scope, vehicle_a, %{"performed_on" => "2026-05-10"})
      _other = maintenance_fixture(other, vehicle_b)

      page = Maintenances.list_maintenances(scope)

      assert Enum.map(page.entries, & &1.id) == [new.id, old.id]
    end

    test "区分・車両・期間で絞り込める", %{manager_a: scope, vehicle_a: vehicle} do
      oil = maintenance_fixture(scope, vehicle, %{"performed_on" => "2026-03-01"})

      _tire =
        maintenance_fixture(scope, vehicle, %{
          "category" => "tire",
          "performed_on" => "2026-03-02"
        })

      assert [found] = Maintenances.list_maintenances(scope, %{"category" => "oil"}).entries
      assert found.id == oil.id

      assert Maintenances.list_maintenances(scope, %{"vehicle_id" => vehicle.id}).total_entries ==
               2

      assert Maintenances.list_maintenances(scope, %{"from" => "2026-03-02"}).total_entries == 1
      assert Maintenances.list_maintenances(scope, %{"to" => "2026-03-01"}).total_entries == 1
    end

    test "車両番号と実施業者で検索できる", %{manager_a: scope, vehicle_a: vehicle} do
      maintenance_fixture(scope, vehicle, %{"vendor" => "ヤナセ整備"})
      maintenance_fixture(scope, vehicle, %{"vendor" => "町の工場"})

      assert [found] = Maintenances.list_maintenances(scope, %{"q" => "ヤナセ"}).entries
      assert found.vendor == "ヤナセ整備"

      assert Maintenances.list_maintenances(scope, %{"q" => vehicle.plate_number}).total_entries ==
               2
    end
  end

  describe "get_maintenance!/2" do
    setup :setup_offices

    test "他拠点の記録は存在しないものとして扱う", %{
      manager_a: scope,
      manager_b: other,
      vehicle_b: vehicle_b
    } do
      maintenance = maintenance_fixture(other, vehicle_b)

      assert_raise Ecto.NoResultsError, fn ->
        Maintenances.get_maintenance!(scope, maintenance.id)
      end
    end
  end

  describe "warnings/2" do
    setup :setup_offices

    test "V-23 車両の最終オドメーターを下回ると警告を返す", %{manager_a: scope, vehicle_a: vehicle} do
      approve_report(scope, vehicle, 50_000)

      changeset =
        Maintenances.change_maintenance(
          %Maintenance{},
          scope,
          valid_maintenance_attributes(vehicle, %{"odometer" => "10000"})
        )

      assert [warning] = Maintenances.warnings(scope, changeset)
      assert warning =~ "50000 km を下回っています"
      assert changeset.valid?
    end

    test "上回っていれば警告は出ない", %{manager_a: scope, vehicle_a: vehicle} do
      changeset =
        Maintenances.change_maintenance(
          %Maintenance{},
          scope,
          valid_maintenance_attributes(vehicle)
        )

      assert Maintenances.warnings(scope, changeset) == []
    end
  end

  # 車両の最終オドメーターは承認済みの日報から更新される（V-18）
  defp approve_report(scope, vehicle, end_odometer) do
    driver = driver_fixture(scope)

    report =
      submitted_report_fixture(scope, vehicle, driver, %{
        "start_odometer" => to_string(end_odometer - 100),
        "end_odometer" => to_string(end_odometer)
      })

    {:ok, _approved} = OperationReports.approve_report(scope, report)
  end

  describe "all_maintenances_for_vehicle/3" do
    setup :setup_offices

    test "指定した車両の記録だけを新しい順に返す", %{manager_a: scope, vehicle_a: vehicle} do
      _old = maintenance_fixture(scope, vehicle, %{"performed_on" => "2026-01-01"})
      new = maintenance_fixture(scope, vehicle, %{"performed_on" => "2026-02-01"})

      assert [first, _second] = Maintenances.all_maintenances_for_vehicle(scope, vehicle.id)
      assert first.id == new.id
    end
  end
end
