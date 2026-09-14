defmodule CoreAppWeb.OperationReportLive.Labels do
  @moduledoc "運行日報の列挙値を日本語表示に変換するモジュールです。"

  alias CoreApp.OperationReports.OperationReport

  @statuses %{
    draft: "下書き",
    submitted: "提出済み",
    approved: "承認済み",
    rejected: "差戻し"
  }

  @doc """
  ステータスの表示名を返します。
  """
  def status(nil), do: "-"
  def status(value), do: Map.fetch!(@statuses, value)

  @doc """
  ステータスのセレクト用選択肢を返します。
  """
  def status_options do
    Enum.map(OperationReport.statuses(), fn value -> {Map.fetch!(@statuses, value), value} end)
  end
end
