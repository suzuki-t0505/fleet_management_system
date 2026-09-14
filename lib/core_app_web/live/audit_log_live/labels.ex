defmodule CoreAppWeb.AuditLogLive.Labels do
  @moduledoc "監査ログの列挙値を日本語表示に変換するモジュールです。"

  alias CoreApp.AuditLogs.AuditLog

  @actions %{
    create: "登録",
    update: "更新",
    delete: "削除",
    approve: "承認",
    reject: "差戻し",
    share: "全社共有",
    role_change: "権限変更"
  }

  # 監査ログに記録されるリソース種別。Context が記録する文字列と対応させる。
  @resource_types [
    {"車両", "vehicle"},
    {"運転者", "driver"},
    {"運行日報", "operation_report"},
    {"点検整備", "maintenance"},
    {"事故・ヒヤリ", "incident"},
    {"ユーザー", "user"}
  ]

  @doc """
  操作の表示名を返します。
  """
  def action(nil), do: "-"
  def action(value), do: Map.fetch!(@actions, value)

  @doc """
  リソース種別の表示名を返します。未知の種別はそのまま返します。
  """
  def resource_type(nil), do: "-"

  def resource_type(value) do
    Enum.find_value(@resource_types, value, fn {label, key} -> key == value && label end)
  end

  @doc """
  操作のセレクト用選択肢を返します。
  """
  def action_options, do: Enum.map(AuditLog.actions(), &{Map.fetch!(@actions, &1), &1})

  @doc """
  リソース種別のセレクト用選択肢を返します。
  """
  def resource_type_options, do: @resource_types
end
