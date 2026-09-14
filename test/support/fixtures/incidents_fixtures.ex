defmodule CoreApp.IncidentsFixtures do
  @moduledoc """
  事故・ヒヤリのテストデータを生成します。
  """

  alias CoreApp.Accounts.Scope
  alias CoreApp.Incidents

  @doc """
  報告内容の入力値を返します。`vehicle` は呼び出し側で渡します。
  """
  def valid_incident_attributes(vehicle, attrs \\ %{}) do
    occurred_at = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)

    Enum.into(attrs, %{
      "vehicle_id" => vehicle.id,
      "occurred_at" => DateTime.to_iso8601(occurred_at),
      "category" => "near_miss",
      "place" => "東京都港区の交差点",
      "weather" => "clear",
      "description" => "前方の車両が急停止し、追突しそうになった"
    })
  end

  def incident_fixture(%Scope{} = scope, vehicle, attrs \\ %{}) do
    {:ok, incident} =
      Incidents.create_incident(scope, valid_incident_attributes(vehicle, attrs))

    incident
  end

  @doc """
  改善策まで登録した（承認待ちの）記録を作成します。
  """
  def countermeasure_reported_fixture(%Scope{} = scope, vehicle, attrs \\ %{}) do
    incident = incident_fixture(scope, vehicle, attrs)
    {:ok, incident} = Incidents.start_analysis(scope, incident)

    {:ok, incident} =
      Incidents.report_countermeasure(scope, incident, %{
        "direct_cause" => "車間距離が不足していた",
        "countermeasure" => "車間距離の確保を朝礼で周知する"
      })

    incident
  end
end
