defmodule CoreApp.VehiclesTest do
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.AuditLogs.AuditLog
  alias CoreApp.Vehicles
  alias CoreApp.Vehicles.Vehicle

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

  describe "create_vehicle/3" do
    setup :setup_offices

    test "必須項目があれば登録できる", %{manager_a: scope, office_a: office} do
      assert {:ok, %Vehicle{} = vehicle} =
               Vehicles.create_vehicle(scope, valid_vehicle_attributes())

      assert vehicle.office_id == office.id
      assert vehicle.status == :active
      assert String.length(vehicle.id) == 26
    end

    test "運行管理者は他拠点を指定しても自拠点で登録される", %{manager_a: scope, office_a: office_a, office_b: office_b} do
      {:ok, vehicle} =
        Vehicles.create_vehicle(scope, valid_vehicle_attributes(%{"office_id" => office_b.id}))

      assert vehicle.office_id == office_a.id
    end

    test "管理者は拠点を指定して登録できる", %{admin: scope, office_b: office_b} do
      {:ok, vehicle} =
        Vehicles.create_vehicle(scope, valid_vehicle_attributes(%{"office_id" => office_b.id}))

      assert vehicle.office_id == office_b.id
    end

    test "必須項目が無い場合はエラーを返す", %{manager_a: scope} do
      assert {:error, changeset} = Vehicles.create_vehicle(scope, %{})

      errors = errors_on(changeset)
      assert "can't be blank" in errors.plate_number
      assert "can't be blank" in errors.vin
      assert "can't be blank" in errors.inspection_expires_on
      assert "can't be blank" in errors.liability_insurance_expires_on
    end

    test "V-1 車両番号は全社で一意", %{manager_a: scope_a, manager_b: scope_b} do
      {:ok, _vehicle} =
        Vehicles.create_vehicle(scope_a, valid_vehicle_attributes(%{"plate_number" => "品川100あ1"}))

      assert {:error, changeset} =
               Vehicles.create_vehicle(
                 scope_b,
                 valid_vehicle_attributes(%{"plate_number" => "品川100あ1"})
               )

      assert %{plate_number: ["この車両番号は既に登録されています"]} = errors_on(changeset)
    end

    test "V-2 期限日は初度登録年月より前にできない", %{manager_a: scope} do
      assert {:error, changeset} =
               Vehicles.create_vehicle(
                 scope,
                 valid_vehicle_attributes(%{
                   "first_registered_on" => "2020-04-01",
                   "inspection_expires_on" => "2019-12-31"
                 })
               )

      assert %{inspection_expires_on: ["は初度登録年月より後の日付を入力してください"]} = errors_on(changeset)
    end

    test "初度登録年月に未来日は入力できない", %{manager_a: scope} do
      future = Date.add(CoreApp.Utils.ConvertDatetime.today(), 1)

      assert {:error, changeset} =
               Vehicles.create_vehicle(
                 scope,
                 valid_vehicle_attributes(%{"first_registered_on" => Date.to_iso8601(future)})
               )

      assert %{first_registered_on: ["に未来の日付は入力できません"]} = errors_on(changeset)
    end

    test "数値項目は0より大きい必要がある", %{manager_a: scope} do
      assert {:error, changeset} =
               Vehicles.create_vehicle(scope, valid_vehicle_attributes(%{"capacity_kg" => "0"}))

      assert %{capacity_kg: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "監査ログが同一トランザクションで記録される", %{manager_a: scope} do
      {:ok, vehicle} = Vehicles.create_vehicle(scope, valid_vehicle_attributes())

      assert [log] = Repo.all(AuditLog)
      assert log.action == :create
      assert log.resource_type == "vehicle"
      assert log.resource_id == vehicle.id
      assert log.user_id == scope.user.id
      assert log.changes["plate_number"] == vehicle.plate_number
      # 列挙は文字列として保存する
      assert log.changes["vehicle_class"] == "medium"

      # 既定値のままの項目は changeset の変更に含まれないため記録されない
      refute Map.has_key?(log.changes, "status")
    end

    test "登録に失敗した場合は監査ログも残らない", %{manager_a: scope} do
      assert {:error, _changeset} = Vehicles.create_vehicle(scope, %{})

      assert Repo.all(AuditLog) == []
      assert Repo.all(Vehicle) == []
    end
  end

  describe "update_vehicle/4" do
    setup :setup_offices

    test "車両を更新できる", %{manager_a: scope} do
      vehicle = vehicle_fixture(scope)

      assert {:ok, updated} = Vehicles.update_vehicle(scope, vehicle, %{"model_name" => "フォワード"})
      assert updated.model_name == "フォワード"
    end

    test "ステータスを廃車に変更できる", %{manager_a: scope} do
      vehicle = vehicle_fixture(scope)

      assert {:ok, updated} = Vehicles.update_vehicle(scope, vehicle, %{"status" => "scrapped"})
      assert updated.status == :scrapped
    end

    test "更新の監査ログには変更後の値のみが入る", %{manager_a: scope} do
      vehicle = vehicle_fixture(scope)
      Repo.delete_all(AuditLog)

      {:ok, _updated} = Vehicles.update_vehicle(scope, vehicle, %{"status" => "maintenance"})

      assert [log] = Repo.all(AuditLog)
      assert log.action == :update
      assert log.changes == %{"status" => "maintenance"}
    end

    test "運行管理者は他拠点への付け替えができない", %{manager_a: scope, office_a: office_a, office_b: office_b} do
      vehicle = vehicle_fixture(scope)

      {:ok, updated} = Vehicles.update_vehicle(scope, vehicle, %{"office_id" => office_b.id})

      assert updated.office_id == office_a.id
    end
  end

  describe "get_vehicle!/2 のスコープ境界" do
    setup :setup_offices

    test "自拠点の車両は取得できる", %{manager_a: scope} do
      vehicle = vehicle_fixture(scope)

      assert Vehicles.get_vehicle!(scope, vehicle.id).id == vehicle.id
    end

    test "他拠点の車両は取得できない", %{manager_a: scope_a, manager_b: scope_b} do
      vehicle = vehicle_fixture(scope_b)

      assert_raise Ecto.NoResultsError, fn ->
        Vehicles.get_vehicle!(scope_a, vehicle.id)
      end
    end

    test "一般利用者も自拠点の車両のみ取得できる", %{manager_b: scope_b, office_a: office_a} do
      vehicle = vehicle_fixture(scope_b)
      member = user_fixture(%{office_id: office_a.id}) |> Scope.for_user()

      assert_raise Ecto.NoResultsError, fn ->
        Vehicles.get_vehicle!(member, vehicle.id)
      end
    end

    test "管理者は全拠点の車両を取得できる", %{admin: admin, manager_b: scope_b} do
      vehicle = vehicle_fixture(scope_b)

      assert Vehicles.get_vehicle!(admin, vehicle.id).id == vehicle.id
    end
  end

  describe "list_vehicles/2 のスコープ境界" do
    setup :setup_offices

    test "運行管理者には自拠点の車両のみ返す", %{manager_a: scope_a, manager_b: scope_b} do
      mine = vehicle_fixture(scope_a)
      _other = vehicle_fixture(scope_b)

      assert [vehicle] = Vehicles.list_vehicles(scope_a).entries
      assert vehicle.id == mine.id
    end

    test "管理者には全拠点の車両を返す", %{admin: admin, manager_a: scope_a, manager_b: scope_b} do
      vehicle_fixture(scope_a)
      vehicle_fixture(scope_b)

      assert Vehicles.list_vehicles(admin).total_entries == 2
    end

    test "運行管理者が他拠点を指定しても自拠点に限定される", %{manager_a: scope_a, manager_b: scope_b, office_b: office_b} do
      vehicle_fixture(scope_b)

      assert Vehicles.list_vehicles(scope_a, %{"office_id" => office_b.id}).total_entries == 0
    end
  end

  describe "list_vehicles/2 の絞り込み" do
    setup :setup_offices

    test "既定では廃車を除外する", %{manager_a: scope} do
      active = vehicle_fixture(scope)
      scrapped = vehicle_fixture(scope)
      {:ok, _} = Vehicles.update_vehicle(scope, scrapped, %{"status" => "scrapped"})

      entries = Vehicles.list_vehicles(scope).entries

      assert Enum.map(entries, & &1.id) == [active.id]
    end

    test "status=all で廃車を含む", %{manager_a: scope} do
      vehicle_fixture(scope)
      scrapped = vehicle_fixture(scope)
      {:ok, _} = Vehicles.update_vehicle(scope, scrapped, %{"status" => "scrapped"})

      assert Vehicles.list_vehicles(scope, %{"status" => "all"}).total_entries == 2
    end

    test "ステータスで絞り込める", %{manager_a: scope} do
      vehicle_fixture(scope)
      maintenance = vehicle_fixture(scope)
      {:ok, _} = Vehicles.update_vehicle(scope, maintenance, %{"status" => "maintenance"})

      assert [found] = Vehicles.list_vehicles(scope, %{"status" => "maintenance"}).entries
      assert found.id == maintenance.id
    end

    test "車種区分で絞り込める", %{manager_a: scope} do
      large = vehicle_fixture(scope, %{"vehicle_class" => "large"})
      vehicle_fixture(scope, %{"vehicle_class" => "light"})

      assert [found] = Vehicles.list_vehicles(scope, %{"vehicle_class" => "large"}).entries
      assert found.id == large.id
    end

    test "車両番号と車名を部分一致で検索できる", %{manager_a: scope} do
      target = vehicle_fixture(scope, %{"plate_number" => "練馬500さ9999", "model_name" => "キャンター"})
      vehicle_fixture(scope, %{"plate_number" => "品川100あ1111", "model_name" => "エルフ"})

      assert [by_plate] = Vehicles.list_vehicles(scope, %{"q" => "練馬"}).entries
      assert by_plate.id == target.id

      assert [by_model] = Vehicles.list_vehicles(scope, %{"q" => "キャンター"}).entries
      assert by_model.id == target.id
    end

    test "拠点で絞り込める（管理者）", %{
      admin: admin,
      manager_a: scope_a,
      manager_b: scope_b,
      office_a: office_a
    } do
      mine = vehicle_fixture(scope_a)
      vehicle_fixture(scope_b)

      assert [found] = Vehicles.list_vehicles(admin, %{"office_id" => office_a.id}).entries
      assert found.id == mine.id
    end

    test "車両番号の昇順で返す", %{manager_a: scope} do
      vehicle_fixture(scope, %{"plate_number" => "品川100あ30"})
      vehicle_fixture(scope, %{"plate_number" => "品川100あ10"})
      vehicle_fixture(scope, %{"plate_number" => "品川100あ20"})

      plate_numbers = Vehicles.list_vehicles(scope).entries |> Enum.map(& &1.plate_number)

      assert plate_numbers == ["品川100あ10", "品川100あ20", "品川100あ30"]
    end

    test "拠点をpreloadして返す", %{manager_a: scope, office_a: office} do
      vehicle_fixture(scope)

      assert [vehicle] = Vehicles.list_vehicles(scope).entries
      assert vehicle.office.name == office.name
    end
  end

  describe "all_selectable_vehicles/1" do
    setup :setup_offices

    test "廃車を除いた自拠点の車両を返す", %{manager_a: scope, manager_b: scope_b} do
      active = vehicle_fixture(scope)
      scrapped = vehicle_fixture(scope)
      {:ok, _} = Vehicles.update_vehicle(scope, scrapped, %{"status" => "scrapped"})
      vehicle_fixture(scope_b)

      assert Enum.map(Vehicles.all_selectable_vehicles(scope), & &1.id) == [active.id]
    end
  end

  describe "count_vehicles_by_status/1" do
    setup :setup_offices

    test "ステータスごとの台数を返す", %{manager_a: scope} do
      vehicle_fixture(scope)
      vehicle_fixture(scope)
      maintenance = vehicle_fixture(scope)
      {:ok, _} = Vehicles.update_vehicle(scope, maintenance, %{"status" => "maintenance"})

      assert Vehicles.count_vehicles_by_status(scope) == %{active: 2, maintenance: 1}
    end
  end
end
