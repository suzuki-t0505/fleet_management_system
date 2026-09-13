defmodule CoreApp.Accounts.ScopeTest do
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures

  alias CoreApp.Accounts.Scope

  describe "for_user/1" do
    test "利用者の拠点とロールをスコープに載せる" do
      user = user_fixture(%{role: :manager})

      scope = Scope.for_user(user)

      assert scope.user.id == user.id
      assert scope.office_id == user.office_id
      assert scope.role == :manager
      assert is_nil(scope.driver_id)
    end

    test "利用者が無い場合は nil を返す" do
      assert is_nil(Scope.for_user(nil))
    end
  end

  describe "for_user/1 と運転者の紐付け" do
    test "運転者が紐付いた利用者は driver_id が入る" do
      office = CoreApp.OfficesFixtures.office_fixture()
      user = user_fixture(%{office_id: office.id})

      driver =
        CoreApp.DriversFixtures.driver_fixture(
          Scope.for_user(CoreApp.AccountsFixtures.admin_fixture(%{office_id: office.id})),
          %{"user_id" => user.id, "office_id" => office.id}
        )

      scope = user |> CoreApp.Repo.preload(:driver) |> Scope.for_user()

      assert scope.driver_id == driver.id
    end

    test "運転者が紐付いていない場合は nil" do
      user = user_fixture() |> CoreApp.Repo.preload(:driver)

      assert is_nil(Scope.for_user(user).driver_id)
    end

    test "preload していない場合も nil として扱う" do
      user = user_fixture()

      assert is_nil(Scope.for_user(user).driver_id)
    end
  end

  describe "admin?/1" do
    test "管理者のみ真を返す" do
      assert Scope.admin?(Scope.for_user(admin_fixture()))
      refute Scope.admin?(Scope.for_user(manager_fixture()))
      refute Scope.admin?(Scope.for_user(user_fixture()))
      refute Scope.admin?(nil)
    end
  end

  describe "manager?/1" do
    test "運行管理者と管理者が真を返す" do
      assert Scope.manager?(Scope.for_user(admin_fixture()))
      assert Scope.manager?(Scope.for_user(manager_fixture()))
      refute Scope.manager?(Scope.for_user(user_fixture()))
      refute Scope.manager?(nil)
    end
  end

  describe "office_filter/1" do
    test "管理者は全拠点を参照するため nil を返す" do
      assert is_nil(Scope.office_filter(Scope.for_user(admin_fixture())))
    end

    test "運行管理者と一般利用者は自拠点に絞られる" do
      manager = manager_fixture()
      member = user_fixture()

      assert Scope.office_filter(Scope.for_user(manager)) == manager.office_id
      assert Scope.office_filter(Scope.for_user(member)) == member.office_id
    end
  end
end
