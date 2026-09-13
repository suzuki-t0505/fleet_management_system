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
