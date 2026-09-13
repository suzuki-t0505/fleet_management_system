defmodule CoreApp.DriversFixtures do
  @moduledoc """
  運転者のテストデータを生成します。
  """

  import CoreApp.OfficesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Drivers

  def valid_driver_attributes(attrs \\ %{}) do
    number = System.unique_integer([:positive])

    Enum.into(attrs, %{
      "code" => "D#{number}",
      "name" => "運転 太郎",
      "name_kana" => "うんてん たろう",
      "employment_type" => "full_time",
      "hired_on" => "2021-04-01",
      "license_number" => "1234#{number}",
      "license_types" => ["medium", "ordinary"],
      "license_expires_on" => "2029-08-31"
    })
  end

  @doc """
  運転者を作成します。`scope` を渡さない場合は新しい拠点の管理者スコープで作成します。
  """
  def driver_fixture(scope \\ nil, attrs \\ %{})

  def driver_fixture(nil, attrs) do
    office = office_fixture()

    driver_fixture(CoreApp.VehiclesFixtures.admin_scope(), Map.put(attrs, "office_id", office.id))
  end

  def driver_fixture(%Scope{} = scope, attrs) do
    {:ok, driver} = Drivers.create_driver(scope, valid_driver_attributes(attrs))

    driver
  end
end
