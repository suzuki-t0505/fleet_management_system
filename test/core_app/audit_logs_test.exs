defmodule CoreApp.AuditLogsTest do
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.AuditLogs

  setup do
    office = office_fixture()
    admin = admin_fixture(%{office_id: office.id, name: "管理 太郎"}) |> Scope.for_user()
    manager = manager_fixture(%{office_id: office.id, name: "運行 花子"}) |> Scope.for_user()

    vehicle = vehicle_fixture(admin, %{"office_id" => office.id})
    Repo.delete_all(CoreApp.AuditLogs.AuditLog)

    %{admin: admin, manager: manager, vehicle: vehicle}
  end

  describe "list_audit_logs/2" do
    test "新しい順に返す", %{admin: admin, vehicle: vehicle} do
      {:ok, _first} = AuditLogs.record(admin, :create, "vehicle", vehicle)
      {:ok, second} = AuditLogs.record(admin, :update, "vehicle", vehicle)

      assert [latest, _older] = AuditLogs.list_audit_logs(admin).entries
      assert latest.id == second.id
      assert latest.user.name == "管理 太郎"
    end

    test "リソース種別と操作で絞り込める", %{admin: admin, vehicle: vehicle} do
      {:ok, _} = AuditLogs.record(admin, :create, "vehicle", vehicle)
      {:ok, _} = AuditLogs.record(admin, :role_change, "user", admin.user)

      assert [log] = AuditLogs.list_audit_logs(admin, %{"resource_type" => "user"}).entries
      assert log.action == :role_change

      assert [log] = AuditLogs.list_audit_logs(admin, %{"action" => "create"}).entries
      assert log.resource_type == "vehicle"
    end

    test "操作者の氏名・メールアドレスで検索できる", %{admin: admin, manager: manager, vehicle: vehicle} do
      {:ok, _} = AuditLogs.record(admin, :create, "vehicle", vehicle)
      {:ok, _} = AuditLogs.record(manager, :update, "vehicle", vehicle)

      assert [log] = AuditLogs.list_audit_logs(admin, %{"q" => "運行"}).entries
      assert log.user_id == manager.user.id

      assert [log] = AuditLogs.list_audit_logs(admin, %{"q" => manager.user.email}).entries
      assert log.user_id == manager.user.id
    end

    test "操作者IDで絞り込める", %{admin: admin, manager: manager, vehicle: vehicle} do
      {:ok, _} = AuditLogs.record(admin, :create, "vehicle", vehicle)
      {:ok, _} = AuditLogs.record(manager, :update, "vehicle", vehicle)

      assert [log] =
               AuditLogs.list_audit_logs(admin, %{"user_id" => admin.user.id}).entries

      assert log.user_id == admin.user.id
    end

    test "管理者以外は参照できない", %{manager: manager} do
      assert_raise FunctionClauseError, fn -> AuditLogs.list_audit_logs(manager) end
    end
  end
end
