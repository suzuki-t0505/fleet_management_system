defmodule CoreApp.IncidentsTest do
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.DriversFixtures
  import CoreApp.IncidentsFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.AuditLogs.AuditLog
  alias CoreApp.Incidents
  alias CoreApp.Incidents.Incident

  defp setup_offices(_context) do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    manager_a = manager_fixture(%{office_id: office_a.id}) |> Scope.for_user()
    manager_b = manager_fixture(%{office_id: office_b.id}) |> Scope.for_user()
    admin = admin_fixture(%{office_id: office_a.id}) |> Scope.for_user()
    member = user_fixture(%{office_id: office_a.id}) |> Scope.for_user()

    %{
      office_a: office_a,
      office_b: office_b,
      manager_a: manager_a,
      manager_b: manager_b,
      admin: admin,
      member: member,
      vehicle_a: vehicle_fixture(manager_a),
      vehicle_b: vehicle_fixture(manager_b)
    }
  end

  describe "create_incident/3" do
    setup :setup_offices

    test "全ロールが報告できる", %{member: scope, office_a: office, vehicle_a: vehicle} do
      assert {:ok, %Incident{} = incident} =
               Incidents.create_incident(scope, valid_incident_attributes(vehicle))

      assert incident.office_id == office.id
      assert incident.reported_by_user_id == scope.user.id
      assert incident.status == :reported
      refute incident.shared_company_wide
    end

    test "V-24 発生日時に未来日時は登録できない", %{member: scope, vehicle_a: vehicle} do
      future = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_iso8601()

      assert {:error, changeset} =
               Incidents.create_incident(
                 scope,
                 valid_incident_attributes(vehicle, %{"occurred_at" => future})
               )

      assert errors_on(changeset).occurred_at == ["に未来の日時は入力できません"]
    end

    test "必須項目が無い場合はエラーを返す", %{member: scope} do
      assert {:error, changeset} = Incidents.create_incident(scope, %{})

      errors = errors_on(changeset)
      assert "can't be blank" in errors.vehicle_id
      assert "can't be blank" in errors.description
    end

    test "他拠点の車両は選べない", %{member: scope, vehicle_b: vehicle_b} do
      assert {:error, changeset} =
               Incidents.create_incident(scope, valid_incident_attributes(vehicle_b))

      assert errors_on(changeset).vehicle_id == ["は自拠点の車両を選択してください"]
    end

    test "拠点は車両の配置拠点に従う", %{admin: scope, office_b: office_b, vehicle_b: vehicle_b} do
      {:ok, incident} = Incidents.create_incident(scope, valid_incident_attributes(vehicle_b))

      assert incident.office_id == office_b.id
    end

    test "監査ログを記録する", %{member: scope, vehicle_a: vehicle} do
      Repo.delete_all(AuditLog)

      {:ok, incident} = Incidents.create_incident(scope, valid_incident_attributes(vehicle))

      assert [log] = Repo.all(AuditLog)
      assert log.action == :create
      assert log.resource_type == "incident"
      assert log.resource_id == incident.id
    end
  end

  describe "list_incidents/2 の可視範囲" do
    setup :setup_offices

    test "管理者は全件を見られる", %{admin: admin, manager_a: scope_a, manager_b: scope_b} = ctx do
      incident_fixture(scope_a, ctx.vehicle_a)
      incident_fixture(scope_b, ctx.vehicle_b)

      assert Incidents.list_incidents(admin).total_entries == 2
    end

    test "運行管理者は自拠点と全社共有された記録を見られる", ctx do
      %{admin: admin, manager_a: scope_a, manager_b: scope_b} = ctx
      mine = incident_fixture(scope_a, ctx.vehicle_a)
      other = incident_fixture(scope_b, ctx.vehicle_b)
      shared = incident_fixture(scope_b, ctx.vehicle_b, %{"place" => "共有された場所"})
      {:ok, _shared} = Incidents.share_incident(admin, shared, true)

      ids = scope_a |> Incidents.list_incidents() |> Map.fetch!(:entries) |> Enum.map(& &1.id)

      assert mine.id in ids
      assert shared.id in ids
      refute other.id in ids
    end

    test "一般利用者は自分の報告と全社共有された記録を見られる", ctx do
      %{admin: admin, member: member, manager_a: manager} = ctx
      mine = incident_fixture(member, ctx.vehicle_a)
      others = incident_fixture(manager, ctx.vehicle_a, %{"place" => "他人の報告"})
      shared = incident_fixture(manager, ctx.vehicle_a, %{"place" => "共有された場所"})
      {:ok, _shared} = Incidents.share_incident(admin, shared, true)

      ids = member |> Incidents.list_incidents() |> Map.fetch!(:entries) |> Enum.map(& &1.id)

      assert mine.id in ids
      assert shared.id in ids
      refute others.id in ids
    end

    test "一般利用者は自分が運転者の記録も見られる", ctx do
      %{manager_a: manager, office_a: office} = ctx
      driver = driver_fixture(manager)
      user = user_fixture(%{office_id: office.id})
      {:ok, driver} = CoreApp.Drivers.update_driver(manager, driver, %{"user_id" => user.id})
      member = user |> Repo.preload(:driver) |> Scope.for_user()

      incident =
        incident_fixture(manager, ctx.vehicle_a, %{
          "driver_id" => driver.id,
          "place" => "当事者の記録"
        })

      ids = member |> Incidents.list_incidents() |> Map.fetch!(:entries) |> Enum.map(& &1.id)

      assert incident.id in ids
    end

    test "区分・ステータス・期間で絞り込める", ctx do
      %{manager_a: scope} = ctx
      near_miss = incident_fixture(scope, ctx.vehicle_a)
      injury = incident_fixture(scope, ctx.vehicle_a, %{"category" => "injury"})

      assert [found] = Incidents.list_incidents(scope, %{"category" => "injury"}).entries
      assert found.id == injury.id

      {:ok, _analyzing} = Incidents.start_analysis(scope, near_miss)

      assert [found] = Incidents.list_incidents(scope, %{"status" => "analyzing"}).entries
      assert found.id == near_miss.id

      today = CoreApp.Utils.ConvertDatetime.today() |> Date.to_iso8601()
      assert Incidents.list_incidents(scope, %{"from" => today}).total_entries == 2

      tomorrow =
        CoreApp.Utils.ConvertDatetime.today() |> Date.add(1) |> Date.to_iso8601()

      assert Incidents.list_incidents(scope, %{"from" => tomorrow}).total_entries == 0
    end
  end

  describe "状態遷移" do
    setup :setup_offices

    test "報告 → 分析中 → 改善策登録済み → 完了", ctx do
      %{manager_a: scope, member: reporter} = ctx
      incident = incident_fixture(reporter, ctx.vehicle_a)

      assert {:ok, incident} = Incidents.start_analysis(scope, incident)
      assert incident.status == :analyzing

      assert {:ok, incident} =
               Incidents.report_countermeasure(scope, incident, %{
                 "direct_cause" => "車間距離が不足していた",
                 "countermeasure" => "朝礼で周知する"
               })

      assert incident.status == :countermeasure_reported

      assert {:ok, incident} = Incidents.approve_incident(scope, incident)
      assert incident.status == :closed
      assert incident.approved_by_user_id == scope.user.id
      assert incident.approved_at
    end

    test "V-25 直接原因と対策内容が無いと改善策を登録できない", ctx do
      %{manager_a: scope} = ctx
      incident = incident_fixture(scope, ctx.vehicle_a)
      {:ok, incident} = Incidents.start_analysis(scope, incident)

      assert {:error, changeset} = Incidents.report_countermeasure(scope, incident, %{})

      errors = errors_on(changeset)
      assert errors.direct_cause == ["を入力してください"]
      assert errors.countermeasure == ["を入力してください"]
    end

    test "V-26 報告者本人は承認できない", ctx do
      %{manager_a: scope} = ctx
      incident = countermeasure_reported_fixture(scope, ctx.vehicle_a)

      assert Incidents.approve_incident(scope, incident) == {:error, :reporter}
      refute Incidents.approvable?(scope, incident)
    end

    test "報告者以外の運行管理者は承認できる", ctx do
      %{manager_a: scope, office_a: office} = ctx
      other = manager_fixture(%{office_id: office.id}) |> Scope.for_user()
      incident = countermeasure_reported_fixture(scope, ctx.vehicle_a)

      assert Incidents.approvable?(other, incident)
      assert {:ok, %Incident{status: :closed}} = Incidents.approve_incident(other, incident)
    end

    test "差し戻すと分析中に戻る", ctx do
      %{manager_a: scope, office_a: office} = ctx
      other = manager_fixture(%{office_id: office.id}) |> Scope.for_user()
      incident = countermeasure_reported_fixture(scope, ctx.vehicle_a)

      assert {:ok, incident} = Incidents.reject_incident(other, incident)
      assert incident.status == :analyzing
      refute incident.approved_at
    end

    test "一般利用者は分析を開始できない", ctx do
      %{member: member, manager_a: manager} = ctx
      incident = incident_fixture(manager, ctx.vehicle_a)

      assert Incidents.start_analysis(member, incident) == {:error, :unauthorized}
    end

    test "他拠点の運行管理者は操作できない", ctx do
      %{manager_a: scope_a, manager_b: scope_b} = ctx
      incident = incident_fixture(scope_a, ctx.vehicle_a)

      assert Incidents.start_analysis(scope_b, incident) == {:error, :unauthorized}
    end

    test "承認と差戻しと共有を監査ログに記録する", ctx do
      %{manager_a: scope, admin: admin, office_a: office} = ctx
      other = manager_fixture(%{office_id: office.id}) |> Scope.for_user()
      incident = countermeasure_reported_fixture(scope, ctx.vehicle_a)
      Repo.delete_all(AuditLog)

      {:ok, incident} = Incidents.reject_incident(other, incident)
      {:ok, incident} = Incidents.report_countermeasure(scope, incident, %{})
      {:ok, incident} = Incidents.approve_incident(other, incident)
      {:ok, _incident} = Incidents.share_incident(admin, incident, true)

      actions = AuditLog |> Repo.all() |> Enum.map(& &1.action) |> Enum.sort()

      assert :reject in actions
      assert :approve in actions
      assert :share in actions
    end
  end

  describe "編集と匿名化" do
    setup :setup_offices

    test "一般利用者は自分の報告を報告直後だけ編集できる", ctx do
      %{member: member, manager_a: manager} = ctx
      incident = incident_fixture(member, ctx.vehicle_a)

      assert Incidents.editable?(member, incident)

      {:ok, incident} = Incidents.start_analysis(manager, incident)
      refute Incidents.editable?(member, incident)

      assert Incidents.update_incident(member, incident, %{"place" => "別の場所"}) ==
               {:error, :unauthorized}
    end

    test "完了した記録は誰も編集できない", ctx do
      %{manager_a: scope, admin: admin, office_a: office} = ctx
      other = manager_fixture(%{office_id: office.id}) |> Scope.for_user()
      incident = countermeasure_reported_fixture(scope, ctx.vehicle_a)
      {:ok, incident} = Incidents.approve_incident(other, incident)

      refute Incidents.editable?(admin, incident)
      refute Incidents.analyzable?(admin, incident)
    end

    test "V-27 他拠点の利用者には氏名を伏せる", ctx do
      %{admin: admin, manager_a: scope_a, manager_b: scope_b} = ctx
      incident = incident_fixture(scope_a, ctx.vehicle_a)
      {:ok, incident} = Incidents.share_incident(admin, incident, true)

      assert Incidents.anonymize?(scope_b, incident)
      refute Incidents.anonymize?(scope_a, incident)
      refute Incidents.anonymize?(admin, incident)
    end

    test "共有されていない記録は匿名化の対象にならない", ctx do
      %{manager_a: scope_a, manager_b: scope_b} = ctx
      incident = incident_fixture(scope_a, ctx.vehicle_a)

      refute Incidents.anonymize?(scope_b, incident)
    end
  end

  describe "ダッシュボード用の集計" do
    setup :setup_offices

    test "未対応の車両不具合報告を数える", ctx do
      %{manager_a: scope} = ctx
      incident_fixture(scope, ctx.vehicle_a, %{"category" => "single"})
      handled = incident_fixture(scope, ctx.vehicle_a, %{"category" => "single"})
      incident_fixture(scope, ctx.vehicle_a, %{"category" => "near_miss"})
      {:ok, _analyzing} = Incidents.start_analysis(scope, handled)

      assert Incidents.count_open_vehicle_defects(scope) == 1
    end

    test "改善報告が未完了の件数を数える", ctx do
      %{manager_a: scope, office_a: office} = ctx
      other = manager_fixture(%{office_id: office.id}) |> Scope.for_user()
      incident_fixture(scope, ctx.vehicle_a)
      closed = countermeasure_reported_fixture(scope, ctx.vehicle_a)
      {:ok, _closed} = Incidents.approve_incident(other, closed)

      assert Incidents.count_open_incidents(scope) == 1
    end

    test "全社共有された記録を新しい順に返す", ctx do
      %{admin: admin, manager_a: scope} = ctx
      incident = incident_fixture(scope, ctx.vehicle_a)
      {:ok, shared} = Incidents.share_incident(admin, incident, true)
      incident_fixture(scope, ctx.vehicle_a)

      assert [found] = Incidents.all_shared_incidents(scope)
      assert found.id == shared.id
    end
  end
end
