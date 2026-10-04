defmodule CoreApp.DispatchesFixtures do
  @moduledoc """
  配車のテストデータを生成します。
  """

  import CoreApp.DriversFixtures
  import CoreApp.ShippersFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Dispatches

  @doc """
  配車の有効な入力値を返します。荷主・車両・ドライバーは呼び出し側で指定してください。

  日時は `2026-10-01 09:00` から `2026-10-01 12:00`（UTC表記）です。
  """
  def valid_dispatch_attributes(attrs \\ %{}) do
    number = System.unique_integer([:positive])

    Enum.into(attrs, %{
      "title" => "テスト配送#{number}",
      "description" => "テストの配送です",
      "started_at" => "2026-10-01T09:00:00Z",
      "ended_at" => "2026-10-01T12:00:00Z",
      "pricing_type" => "course_total",
      "course_fare_yen" => "30000",
      "toll_yen" => "1500"
    })
  end

  @doc """
  同じ拠点の荷主・車両・ドライバーを作成して、配車の入力値に加えます。
  """
  def dispatch_attributes_for(%Scope{} = scope, attrs \\ %{}) do
    shipper = shipper_fixture(scope)
    vehicle = vehicle_fixture(scope)
    driver = driver_fixture(scope)

    valid_dispatch_attributes(
      Map.merge(
        %{
          "shipper_id" => shipper.id,
          "vehicle_id" => vehicle.id,
          "driver_id" => driver.id
        },
        attrs
      )
    )
  end

  @doc """
  配車を作成します。荷主・車両・ドライバーを指定しない場合は `scope` の拠点に新しく作成します。
  """
  def dispatch_fixture(%Scope{} = scope, attrs \\ %{}) do
    {:ok, dispatch} = Dispatches.create_dispatch(scope, dispatch_attributes_for(scope, attrs))

    dispatch
  end
end
