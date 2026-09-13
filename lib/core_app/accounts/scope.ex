defmodule CoreApp.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `CoreApp.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use in authorization checks,
  or to ensure specific code paths can only be accessed for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias CoreApp.Accounts.User

  defstruct user: nil, office_id: nil, role: nil, driver_id: nil

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{
      user: user,
      office_id: user.office_id,
      role: user.role,
      driver_id: nil
    }
  end

  def for_user(nil), do: nil

  @doc """
  管理者かどうかを返します。全拠点のデータとユーザー管理にアクセスできます。
  """
  def admin?(%__MODULE__{role: :admin}), do: true
  def admin?(_scope), do: false

  @doc """
  運行管理者以上かどうかを返します。管理者は運行管理者の権限をすべて含みます。
  """
  def manager?(%__MODULE__{role: role}), do: role in [:admin, :manager]
  def manager?(_scope), do: false

  @doc """
  スコープが参照できる拠点IDを返します。管理者は全拠点を参照するため `nil` を返します。
  """
  def office_filter(%__MODULE__{role: :admin}), do: nil
  def office_filter(%__MODULE__{office_id: office_id}), do: office_id
end
