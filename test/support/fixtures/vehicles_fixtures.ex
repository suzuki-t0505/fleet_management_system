defmodule CoreApp.VehiclesFixtures do
  @moduledoc """
  車両のテストデータを生成します。
  """

  import CoreApp.OfficesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Vehicles

  def valid_vehicle_attributes(attrs \\ %{}) do
    number = System.unique_integer([:positive])

    Enum.into(attrs, %{
      "plate_number" => "品川100あ#{number}",
      "vin" => "VIN#{number}",
      "vehicle_class" => "medium",
      "maker" => "いすゞ",
      "model_name" => "エルフ",
      "first_registered_on" => "2020-04-01",
      "status" => "active",
      "inspection_expires_on" => "2027-03-31",
      "liability_insurance_expires_on" => "2027-04-30"
    })
  end

  @doc """
  車両を作成します。`scope` を渡さない場合は新しい拠点の管理者スコープで作成します。
  """
  def vehicle_fixture(scope \\ nil, attrs \\ %{})

  def vehicle_fixture(nil, attrs) do
    office = office_fixture()

    vehicle_fixture(admin_scope(), Map.put_new(attrs, "office_id", office.id))
  end

  def vehicle_fixture(%Scope{} = scope, attrs) do
    {:ok, vehicle} = Vehicles.create_vehicle(scope, valid_vehicle_attributes(attrs))

    vehicle
  end

  @doc """
  監査ログの記録に使う利用者を伴う管理者スコープを返します。
  """
  def admin_scope do
    CoreApp.AccountsFixtures.admin_fixture() |> Scope.for_user()
  end
end
