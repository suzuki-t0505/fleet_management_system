defmodule CoreApp.ShippersTest do
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.ShippersFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.AuditLogs.AuditLog
  alias CoreApp.Shippers
  alias CoreApp.Shippers.Shipper

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
      admin: admin
    }
  end

  describe "create_shipper/3" do
    setup :setup_offices

    test "必須項目があれば登録できる", %{manager_a: scope, office_a: office} do
      assert {:ok, %Shipper{} = shipper} =
               Shippers.create_shipper(scope, valid_shipper_attributes())

      assert shipper.office_id == office.id
      assert shipper.status == :active
    end

    test "運行管理者は他拠点を指定しても自拠点で登録される", %{
      manager_a: scope,
      office_a: office_a,
      office_b: office_b
    } do
      {:ok, shipper} =
        Shippers.create_shipper(scope, valid_shipper_attributes(%{"office_id" => office_b.id}))

      assert shipper.office_id == office_a.id
    end

    test "管理者は拠点を指定して登録できる", %{admin: scope, office_b: office_b} do
      {:ok, shipper} =
        Shippers.create_shipper(scope, valid_shipper_attributes(%{"office_id" => office_b.id}))

      assert shipper.office_id == office_b.id
    end

    test "荷主名が無い場合はエラーを返す", %{manager_a: scope} do
      assert {:error, changeset} = Shippers.create_shipper(scope, %{})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "同じ拠点で同名の荷主は登録できない", %{manager_a: scope} do
      shipper_fixture(scope, %{"name" => "重複荷主"})

      assert {:error, changeset} =
               Shippers.create_shipper(scope, valid_shipper_attributes(%{"name" => "重複荷主"}))

      assert "この荷主名は既に登録されています" in errors_on(changeset).name
    end

    test "別の拠点なら同名でも登録できる", %{manager_a: a, manager_b: b} do
      shipper_fixture(a, %{"name" => "共通荷主"})

      assert {:ok, _} =
               Shippers.create_shipper(b, valid_shipper_attributes(%{"name" => "共通荷主"}))
    end

    test "監査ログが記録される", %{manager_a: scope} do
      {:ok, shipper} = Shippers.create_shipper(scope, valid_shipper_attributes())

      log = Repo.get_by!(AuditLog, resource_type: "shipper", resource_id: shipper.id)
      assert log.action == :create
    end

    test "失敗時は監査ログを残さない", %{manager_a: scope} do
      {:error, _} = Shippers.create_shipper(scope, %{})

      refute Repo.get_by(AuditLog, resource_type: "shipper")
    end
  end

  describe "update_shipper/4" do
    setup :setup_offices

    test "無効化できる", %{manager_a: scope} do
      shipper = shipper_fixture(scope)

      assert {:ok, updated} = Shippers.update_shipper(scope, shipper, %{"status" => "inactive"})
      assert updated.status == :inactive

      assert Repo.get_by!(AuditLog,
               resource_type: "shipper",
               resource_id: shipper.id,
               action: :update
             )
    end
  end

  describe "get_shipper!/2" do
    setup :setup_offices

    test "他拠点の荷主は取得できない", %{manager_a: a, manager_b: b} do
      shipper = shipper_fixture(b)

      assert_raise Ecto.NoResultsError, fn -> Shippers.get_shipper!(a, shipper.id) end
    end

    test "管理者は他拠点の荷主も取得できる", %{admin: admin, manager_b: b} do
      shipper = shipper_fixture(b)

      assert Shippers.get_shipper!(admin, shipper.id).id == shipper.id
    end
  end

  describe "list_shippers/2" do
    setup :setup_offices

    test "自拠点の有効な荷主のみ返す", %{manager_a: a, manager_b: b} do
      mine = shipper_fixture(a, %{"name" => "自拠点荷主"})
      shipper_fixture(a, %{"name" => "無効荷主", "status" => "inactive"})
      shipper_fixture(b, %{"name" => "他拠点荷主"})

      assert [%{id: id}] = Shippers.list_shippers(a).entries
      assert id == mine.id
    end

    test "status=all で無効も含める", %{manager_a: a} do
      shipper_fixture(a, %{"name" => "有効荷主"})
      shipper_fixture(a, %{"name" => "無効荷主", "status" => "inactive"})

      assert length(Shippers.list_shippers(a, %{"status" => "all"}).entries) == 2
    end

    test "キーワードで絞り込める", %{manager_a: a} do
      shipper_fixture(a, %{"name" => "北海道物流"})
      shipper_fixture(a, %{"name" => "九州運輸"})

      assert [%{name: "北海道物流"}] = Shippers.list_shippers(a, %{"q" => "北海道"}).entries
    end
  end

  describe "all_selectable_shippers/2" do
    setup :setup_offices

    test "無効な荷主は選択肢に出ない", %{manager_a: a} do
      shipper_fixture(a, %{"status" => "inactive"})
      active = shipper_fixture(a)

      assert [%{id: id}] = Shippers.all_selectable_shippers(a)
      assert id == active.id
    end

    test "現在の荷主は無効でも選択肢に含める", %{manager_a: a} do
      inactive = shipper_fixture(a, %{"status" => "inactive"})

      assert [%{id: id}] = Shippers.all_selectable_shippers(a, inactive.id)
      assert id == inactive.id
    end
  end
end
