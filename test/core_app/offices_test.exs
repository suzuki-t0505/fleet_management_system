defmodule CoreApp.OfficesTest do
  use CoreApp.DataCase, async: true

  import CoreApp.OfficesFixtures

  alias CoreApp.Offices
  alias CoreApp.Offices.Office

  describe "all_offices/0" do
    test "有効な拠点のみを拠点コードの昇順で返す" do
      office_b = office_fixture(%{"code" => "B001"})
      office_a = office_fixture(%{"code" => "A001"})
      _inactive = office_fixture(%{"code" => "C001", "active" => false})

      assert [%Office{id: first}, %Office{id: second}] = Offices.all_offices()
      assert first == office_a.id
      assert second == office_b.id
    end

    test "拠点が無い場合は空リストを返す" do
      assert Offices.all_offices() == []
    end
  end

  describe "get_office!/1" do
    test "IDで拠点を取得する" do
      office = office_fixture()

      assert Offices.get_office!(office.id).id == office.id
    end

    test "存在しないIDでは例外を発生させる" do
      assert_raise Ecto.NoResultsError, fn ->
        Offices.get_office!(Ecto.ULID.generate())
      end
    end

    test "無効化された拠点もIDでは取得できる" do
      office = office_fixture(%{"active" => false})

      assert Offices.get_office!(office.id).active == false
    end
  end

  describe "create_office/1" do
    test "必須項目があれば作成できる" do
      assert {:ok, %Office{} = office} =
               Offices.create_office(%{"code" => "HQ", "name" => "本社"})

      assert office.code == "HQ"
      assert office.active == true
      assert String.length(office.id) == 26
    end

    test "拠点コードと拠点名は必須" do
      assert {:error, changeset} = Offices.create_office(%{})

      assert %{code: ["can't be blank"], name: ["can't be blank"]} = errors_on(changeset)
    end

    test "拠点コードは重複できない" do
      office_fixture(%{"code" => "HQ"})

      assert {:error, changeset} = Offices.create_office(%{"code" => "HQ", "name" => "本社"})
      assert %{code: ["has already been taken"]} = errors_on(changeset)
    end

    test "郵便番号の形式を検証する" do
      assert {:error, changeset} =
               Offices.create_office(%{"code" => "HQ", "name" => "本社", "postal_code" => "1000"})

      assert %{postal_code: ["は 000-0000 の形式で入力してください"]} = errors_on(changeset)
    end
  end

  describe "update_office/2" do
    test "拠点を更新できる" do
      office = office_fixture()

      assert {:ok, %Office{} = updated} = Offices.update_office(office, %{"name" => "大阪営業所"})
      assert updated.name == "大阪営業所"
    end

    test "無効化できる" do
      office = office_fixture()

      assert {:ok, %Office{active: false}} = Offices.update_office(office, %{"active" => false})
      assert Offices.all_offices() == []
    end
  end
end
