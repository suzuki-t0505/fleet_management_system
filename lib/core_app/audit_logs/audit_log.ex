defmodule CoreApp.AuditLogs.AuditLog do
  @moduledoc false
  use CoreApp.Schema
  import Ecto.Changeset

  alias CoreApp.Accounts.User

  @actions ~w(create update delete approve reject share role_change)a

  schema "audit_logs" do
    field :action, Ecto.Enum, values: @actions
    field :resource_type, :string
    field :resource_id, Ecto.ULID
    field :changes, :map
    field :ip_address, :string

    belongs_to(:user, User)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  記録できる操作の一覧を返します。
  """
  def actions, do: @actions

  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [:user_id, :action, :resource_type, :resource_id, :changes, :ip_address])
    |> validate_required([:user_id, :action, :resource_type, :resource_id])
    |> assoc_constraint(:user)
  end
end
