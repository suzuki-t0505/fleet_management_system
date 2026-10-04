defmodule CoreApp.ShippersFixtures do
  @moduledoc """
  荷主のテストデータを生成します。
  """

  import CoreApp.OfficesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Shippers

  def valid_shipper_attributes(attrs \\ %{}) do
    number = System.unique_integer([:positive])

    Enum.into(attrs, %{
      "name" => "テスト荷主#{number}",
      "code" => "S#{number}",
      "status" => "active"
    })
  end

  @doc """
  荷主を作成します。`scope` を渡さない場合は新しい拠点の管理者スコープで作成します。
  """
  def shipper_fixture(scope \\ nil, attrs \\ %{})

  def shipper_fixture(nil, attrs) do
    office = office_fixture()

    shipper_fixture(
      CoreApp.VehiclesFixtures.admin_scope(),
      Map.put_new(attrs, "office_id", office.id)
    )
  end

  def shipper_fixture(%Scope{} = scope, attrs) do
    {:ok, shipper} = Shippers.create_shipper(scope, valid_shipper_attributes(attrs))

    shipper
  end
end
