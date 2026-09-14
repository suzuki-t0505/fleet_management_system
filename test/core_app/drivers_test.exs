defmodule CoreApp.DriversTest do
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.AuditLogs.AuditLog
  alias CoreApp.Drivers
  alias CoreApp.Drivers.Driver
  alias CoreApp.Utils.ConvertDatetime

  defp setup_offices(_context) do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    %{
      office_a: office_a,
      office_b: office_b,
      manager_a: manager_fixture(%{office_id: office_a.id}) |> Scope.for_user(),
      manager_b: manager_fixture(%{office_id: office_b.id}) |> Scope.for_user(),
      admin: admin_fixture(%{office_id: office_a.id}) |> Scope.for_user()
    }
  end

  describe "create_driver/3" do
    setup :setup_offices

    test "必須項目があれば登録できる", %{manager_a: scope, office_a: office} do
      assert {:ok, %Driver{} = driver} = Drivers.create_driver(scope, valid_driver_attributes())

      assert driver.office_id == office.id
      assert driver.employment_type == :full_time
      assert driver.license_types == [:medium, :ordinary]
    end

    test "運行管理者は他拠点を指定しても自拠点で登録される", %{manager_a: scope, office_a: a, office_b: b} do
      {:ok, driver} =
        Drivers.create_driver(scope, valid_driver_attributes(%{"office_id" => b.id}))

      assert driver.office_id == a.id
    end

    test "必須項目が無い場合はエラーを返す", %{manager_a: scope} do
      assert {:error, changeset} = Drivers.create_driver(scope, %{})

      errors = errors_on(changeset)
      assert "can't be blank" in errors.code
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.name_kana
      assert "can't be blank" in errors.license_number
      assert "を1つ以上選択してください" in errors.license_types
    end

    test "運転者コードは全社で一意", %{manager_a: scope_a, manager_b: scope_b} do
      driver_fixture(scope_a, %{"code" => "D001"})

      assert {:error, changeset} =
               Drivers.create_driver(scope_b, valid_driver_attributes(%{"code" => "D001"}))

      assert %{code: ["この運転者コードは既に登録されています"]} = errors_on(changeset)
    end

    test "免許種類が空の場合はエラーになる", %{manager_a: scope} do
      assert {:error, changeset} =
               Drivers.create_driver(scope, valid_driver_attributes(%{"license_types" => []}))

      assert %{license_types: ["を1つ以上選択してください"]} = errors_on(changeset)
    end

    test "入社年月日に未来日は入力できない", %{manager_a: scope} do
      future = Date.add(ConvertDatetime.today(), 1)

      assert {:error, changeset} =
               Drivers.create_driver(
                 scope,
                 valid_driver_attributes(%{"hired_on" => Date.to_iso8601(future)})
               )

      assert %{hired_on: ["に未来の日付は入力できません"]} = errors_on(changeset)
    end

    test "退職年月日は入社年月日より前にできない", %{manager_a: scope} do
      assert {:error, changeset} =
               Drivers.create_driver(
                 scope,
                 valid_driver_attributes(%{
                   "hired_on" => "2021-04-01",
                   "retired_on" => "2020-03-31",
                   "employment_type" => "retired"
                 })
               )

      assert %{retired_on: ["は入社年月日より後の日付を入力してください"]} = errors_on(changeset)
    end

    test "退職年月日を入力する場合は雇用区分が退職でなければならない", %{manager_a: scope} do
      assert {:error, changeset} =
               Drivers.create_driver(
                 scope,
                 valid_driver_attributes(%{
                   "retired_on" => "2026-03-31",
                   "employment_type" => "full_time"
                 })
               )

      assert %{employment_type: ["は退職年月日を入力する場合「退職」にしてください"]} = errors_on(changeset)
    end

    test "免許証有効期限が過去日でも登録できる（V-6）", %{manager_a: scope} do
      past = Date.add(ConvertDatetime.today(), -10)

      assert {:ok, driver} =
               Drivers.create_driver(
                 scope,
                 valid_driver_attributes(%{"license_expires_on" => Date.to_iso8601(past)})
               )

      assert Driver.license_expired?(driver)
    end

    test "監査ログが記録される", %{manager_a: scope} do
      {:ok, driver} = Drivers.create_driver(scope, valid_driver_attributes())

      assert [log] = Repo.all(AuditLog)
      assert log.action == :create
      assert log.resource_type == "driver"
      assert log.resource_id == driver.id
      assert log.changes["name"] == driver.name
    end

    test "登録に失敗した場合は監査ログも残らない", %{manager_a: scope} do
      assert {:error, _changeset} = Drivers.create_driver(scope, %{})

      assert Repo.all(AuditLog) == []
      assert Repo.all(Driver) == []
    end
  end

  describe "アカウントの紐付け" do
    setup :setup_offices

    test "利用者を紐付けられる", %{manager_a: scope, office_a: office} do
      user = user_fixture(%{office_id: office.id})

      assert {:ok, driver} =
               Drivers.create_driver(scope, valid_driver_attributes(%{"user_id" => user.id}))

      assert driver.user_id == user.id
    end

    test "同じ利用者を2人の運転者に紐付けられない（V-7）", %{manager_a: scope, office_a: office} do
      user = user_fixture(%{office_id: office.id})
      driver_fixture(scope, %{"user_id" => user.id})

      assert {:error, changeset} =
               Drivers.create_driver(scope, valid_driver_attributes(%{"user_id" => user.id}))

      assert %{user_id: ["このアカウントは既に他の運転者に紐付いています"]} = errors_on(changeset)
    end

    test "未紐付けの運転者は複数登録できる", %{manager_a: scope} do
      driver_fixture(scope)

      assert {:ok, _driver} = Drivers.create_driver(scope, valid_driver_attributes())
    end

    test "紐付け候補から他の運転者に紐付いた利用者を除外する", %{manager_a: scope, office_a: office} do
      linked = user_fixture(%{office_id: office.id})
      free = user_fixture(%{office_id: office.id})
      driver_fixture(scope, %{"user_id" => linked.id})

      candidate_ids = Drivers.all_linkable_users(scope) |> Enum.map(& &1.id)

      assert free.id in candidate_ids
      refute linked.id in candidate_ids
    end

    test "編集中の運転者自身に紐付いた利用者は候補に残る", %{manager_a: scope, office_a: office} do
      user = user_fixture(%{office_id: office.id})
      driver = driver_fixture(scope, %{"user_id" => user.id})

      candidate_ids = Drivers.all_linkable_users(scope, driver) |> Enum.map(& &1.id)

      assert user.id in candidate_ids
    end

    test "他拠点の利用者は候補に含まれない", %{manager_a: scope, office_b: office_b} do
      other = user_fixture(%{office_id: office_b.id})

      refute other.id in (Drivers.all_linkable_users(scope) |> Enum.map(& &1.id))
    end

    test "無効化された利用者は候補に含まれない", %{manager_a: scope, office_a: office} do
      user = user_fixture(%{office_id: office.id})
      {:ok, _user} = CoreApp.Accounts.update_user_profile(user, %{"active" => false})

      refute user.id in (Drivers.all_linkable_users(scope) |> Enum.map(& &1.id))
    end

    test "get_driver_by_user/1 で利用者から運転者を引ける", %{manager_a: scope, office_a: office} do
      user = user_fixture(%{office_id: office.id})
      driver = driver_fixture(scope, %{"user_id" => user.id})

      assert Drivers.get_driver_by_user(user.id).id == driver.id
      assert is_nil(Drivers.get_driver_by_user(Ecto.ULID.generate()))
    end
  end

  describe "update_driver/4" do
    setup :setup_offices

    test "運転者を更新できる", %{manager_a: scope} do
      driver = driver_fixture(scope)

      assert {:ok, updated} = Drivers.update_driver(scope, driver, %{"name" => "運転 次郎"})
      assert updated.name == "運転 次郎"
    end

    test "退職にできる", %{manager_a: scope} do
      driver = driver_fixture(scope)

      assert {:ok, updated} =
               Drivers.update_driver(scope, driver, %{
                 "employment_type" => "retired",
                 "retired_on" => "2026-08-31"
               })

      assert updated.employment_type == :retired
    end

    test "更新の監査ログには変更後の値のみが入る", %{manager_a: scope} do
      driver = driver_fixture(scope)
      Repo.delete_all(AuditLog)

      {:ok, _updated} = Drivers.update_driver(scope, driver, %{"name" => "運転 花子"})

      assert [log] = Repo.all(AuditLog)
      assert log.changes == %{"name" => "運転 花子"}
    end
  end

  describe "スコープ境界" do
    setup :setup_offices

    test "他拠点の運転者は取得できない", %{manager_a: scope_a, manager_b: scope_b} do
      driver = driver_fixture(scope_b)

      assert_raise Ecto.NoResultsError, fn -> Drivers.get_driver!(scope_a, driver.id) end
    end

    test "管理者は全拠点の運転者を取得できる", %{admin: admin, manager_b: scope_b} do
      driver = driver_fixture(scope_b)

      assert Drivers.get_driver!(admin, driver.id).id == driver.id
    end

    test "運行管理者の一覧には自拠点のみ返す", %{manager_a: scope_a, manager_b: scope_b} do
      mine = driver_fixture(scope_a)
      driver_fixture(scope_b)

      assert [driver] = Drivers.list_drivers(scope_a).entries
      assert driver.id == mine.id
    end

    test "管理者の一覧には全拠点を返す", %{admin: admin, manager_a: a, manager_b: b} do
      driver_fixture(a)
      driver_fixture(b)

      assert Drivers.list_drivers(admin).total_entries == 2
    end

    test "他拠点の運転者は更新できない", %{manager_a: scope_a, manager_b: scope_b} do
      driver = driver_fixture(scope_b)

      assert_raise Ecto.NoResultsError, fn -> Drivers.get_driver!(scope_a, driver.id) end
    end
  end

  describe "list_drivers/2 の絞り込み" do
    setup :setup_offices

    test "既定では退職者を除外する", %{manager_a: scope} do
      active = driver_fixture(scope)
      retired = driver_fixture(scope)

      {:ok, _} =
        Drivers.update_driver(scope, retired, %{
          "employment_type" => "retired",
          "retired_on" => "2026-08-31"
        })

      assert Enum.map(Drivers.list_drivers(scope).entries, & &1.id) == [active.id]
    end

    test "employment_type=all で退職者を含む", %{manager_a: scope} do
      driver_fixture(scope)
      retired = driver_fixture(scope)

      {:ok, _} =
        Drivers.update_driver(scope, retired, %{
          "employment_type" => "retired",
          "retired_on" => "2026-08-31"
        })

      assert Drivers.list_drivers(scope, %{"employment_type" => "all"}).total_entries == 2
    end

    test "氏名・かな・コードで検索できる", %{manager_a: scope} do
      target =
        driver_fixture(scope, %{
          "code" => "D-SEARCH",
          "name" => "検索 対象",
          "name_kana" => "けんさく たいしょう"
        })

      driver_fixture(scope, %{"name" => "他の人", "name_kana" => "ほかのひと"})

      assert [by_name] = Drivers.list_drivers(scope, %{"q" => "検索"}).entries
      assert by_name.id == target.id

      assert [by_kana] = Drivers.list_drivers(scope, %{"q" => "けんさく"}).entries
      assert by_kana.id == target.id

      assert [by_code] = Drivers.list_drivers(scope, %{"q" => "D-SEARCH"}).entries
      assert by_code.id == target.id
    end

    test "氏名かなの昇順で返す", %{manager_a: scope} do
      driver_fixture(scope, %{"name_kana" => "さとう"})
      driver_fixture(scope, %{"name_kana" => "あおき"})
      driver_fixture(scope, %{"name_kana" => "かとう"})

      assert Enum.map(Drivers.list_drivers(scope).entries, & &1.name_kana) ==
               ["あおき", "かとう", "さとう"]
    end
  end

  describe "all_selectable_drivers/1" do
    setup :setup_offices

    test "退職者を除いた自拠点の運転者を返す（V-8）", %{manager_a: scope, manager_b: scope_b} do
      active = driver_fixture(scope)
      retired = driver_fixture(scope)

      {:ok, _} =
        Drivers.update_driver(scope, retired, %{
          "employment_type" => "retired",
          "retired_on" => "2026-08-31"
        })

      driver_fixture(scope_b)

      assert Enum.map(Drivers.all_selectable_drivers(scope), & &1.id) == [active.id]
    end
  end

  describe "count_drivers_by_employment_type/1" do
    setup :setup_offices

    test "雇用区分ごとの人数を返す", %{manager_a: scope} do
      driver_fixture(scope)
      driver_fixture(scope)
      driver_fixture(scope, %{"employment_type" => "contract"})

      assert Drivers.count_drivers_by_employment_type(scope) == %{full_time: 2, contract: 1}
    end
  end
end
