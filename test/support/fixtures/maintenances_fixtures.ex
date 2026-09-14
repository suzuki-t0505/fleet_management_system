defmodule CoreApp.MaintenancesFixtures do
  @moduledoc """
  点検整備記録のテストデータを生成します。
  """

  alias CoreApp.Accounts.Scope
  alias CoreApp.Maintenances
  alias CoreApp.Utils.ConvertDatetime

  @doc """
  点検整備記録の入力値を返します。`vehicle` は呼び出し側で渡します。
  """
  def valid_maintenance_attributes(vehicle, attrs \\ %{}) do
    Enum.into(attrs, %{
      "vehicle_id" => vehicle.id,
      "performed_on" => Date.to_iso8601(ConvertDatetime.today()),
      "category" => "oil",
      "odometer" => "12000",
      "vendor" => "テスト整備工場",
      "cost_yen" => "8000"
    })
  end

  def maintenance_fixture(%Scope{} = scope, vehicle, attrs \\ %{}) do
    {:ok, maintenance} =
      Maintenances.create_maintenance(scope, valid_maintenance_attributes(vehicle, attrs))

    maintenance
  end
end
