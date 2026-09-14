defmodule CoreApp.Alerts.Deadline do
  @moduledoc """
  監視対象の期限1件を表す値オブジェクトです。

  車両・運転者の複数のカラムを横断した一覧を扱うため、テーブルを持ちません。
  一覧画面と通知ジョブが同じ構造体を見ることで、残日数の数え方をそろえます。
  """

  alias CoreApp.Utils.ConvertDatetime

  defstruct [
    :target_type,
    :target_id,
    :target_name,
    :office_id,
    :office_name,
    :alert_type,
    :deadline_on,
    :days_left
  ]

  @alert_type_labels %{
    inspection: "車検満了日",
    liability_insurance: "自賠責保険満了日",
    voluntary_insurance: "任意保険満了日",
    periodic_3m: "3ヶ月点検予定日",
    periodic_12m: "12ヶ月点検予定日",
    license: "免許証有効期限"
  }

  @target_type_labels %{vehicle: "車両", driver: "運転者"}

  @alert_types ~w(inspection liability_insurance voluntary_insurance periodic_3m periodic_12m license)a

  @doc """
  クエリの行から期限を組み立てます。残日数は渡した日付を基準に算出します。
  """
  def new(row, %Date{} = today) do
    %__MODULE__{
      target_type: to_atom(row.target_type),
      target_id: row.target_id,
      target_name: row.target_name,
      office_id: row.office_id,
      office_name: Map.get(row, :office_name),
      alert_type: to_atom(row.alert_type),
      deadline_on: row.deadline_on,
      days_left: Date.diff(row.deadline_on, today)
    }
  end

  def new(row), do: new(row, ConvertDatetime.today())

  @doc """
  期限種別の一覧を返します。
  """
  def alert_types, do: @alert_types

  @doc """
  期限種別の表示名を返します。
  """
  def alert_type_label(alert_type), do: Map.fetch!(@alert_type_labels, alert_type)

  @doc """
  対象種別の表示名を返します。
  """
  def target_type_label(target_type), do: Map.fetch!(@target_type_labels, target_type)

  @doc """
  Obanのジョブ引数に載せられる形（文字列キーのマップ）へ変換します。
  """
  def to_args(%__MODULE__{} = deadline) do
    %{
      "target_type" => to_string(deadline.target_type),
      "target_id" => deadline.target_id,
      "target_name" => deadline.target_name,
      "office_id" => deadline.office_id,
      "office_name" => deadline.office_name,
      "alert_type" => to_string(deadline.alert_type),
      "deadline_on" => Date.to_iso8601(deadline.deadline_on),
      "days_left" => deadline.days_left
    }
  end

  @doc """
  `to_args/1` で変換したジョブ引数から期限を復元します。
  """
  def from_args(%{} = args) do
    %__MODULE__{
      target_type: to_atom(args["target_type"]),
      target_id: args["target_id"],
      target_name: args["target_name"],
      office_id: args["office_id"],
      office_name: args["office_name"],
      alert_type: to_atom(args["alert_type"]),
      deadline_on: Date.from_iso8601!(args["deadline_on"]),
      days_left: args["days_left"]
    }
  end

  @doc """
  期限を超過しているかを返します。
  """
  def overdue?(%__MODULE__{days_left: days_left}), do: days_left < 0

  defp to_atom(value) when is_binary(value), do: String.to_existing_atom(value)
  defp to_atom(value) when is_atom(value), do: value
end
