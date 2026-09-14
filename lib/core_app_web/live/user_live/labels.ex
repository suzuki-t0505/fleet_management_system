defmodule CoreAppWeb.UserLive.Labels do
  @moduledoc "利用者の列挙値を日本語表示に変換するモジュールです。"

  alias CoreApp.Accounts.User

  @roles %{admin: "管理者", manager: "運行管理者", member: "一般利用者"}

  @statuses %{active: "有効", inactive: "無効", locked: "ロック中"}

  @active_options [{"有効のみ", "true"}, {"無効のみ", "false"}, {"すべて", "all"}]

  @doc """
  ロールの表示名を返します。
  """
  def role(nil), do: "-"
  def role(value), do: Map.get(@roles, value, "-")

  @doc """
  アカウント状態の表示名を返します。
  """
  def status(nil), do: "-"
  def status(value), do: Map.fetch!(@statuses, value)

  @doc """
  ロールのセレクト用選択肢を返します。
  """
  def role_options, do: Enum.map(User.roles(), &{Map.fetch!(@roles, &1), &1})

  @doc """
  有効フラグの絞り込み用選択肢を返します。
  """
  def active_options, do: @active_options
end
