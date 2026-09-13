defmodule CoreApp.OfficesFixtures do
  @moduledoc """
  拠点のテストデータを生成します。
  """

  alias CoreApp.Offices

  def office_fixture(attrs \\ %{}) do
    code = "OF#{System.unique_integer([:positive])}"

    {:ok, office} =
      attrs
      |> Enum.into(%{
        "code" => code,
        "name" => "テスト営業所",
        "postal_code" => "100-0001",
        "address" => "東京都千代田区1-1-1",
        "phone" => "03-0000-0000"
      })
      |> Offices.create_office()

    office
  end
end
