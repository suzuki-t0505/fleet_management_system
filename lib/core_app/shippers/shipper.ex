defmodule CoreApp.Shippers.Shipper do
  @moduledoc false
  use CoreApp.Schema
  import Ecto.Changeset

  alias CoreApp.Offices.Office

  @statuses ~w(active inactive)a

  schema "shippers" do
    field :name, :string
    field :code, :string
    field :note, :string
    field :status, Ecto.Enum, values: @statuses, default: :active

    belongs_to(:office, Office)

    timestamps(type: :utc_datetime)
  end

  @doc """
  荷主ステータスの一覧を返します。
  """
  def statuses, do: @statuses

  def changeset(shipper, attrs) do
    shipper
    |> cast(attrs, [:office_id, :name, :code, :note, :status])
    |> validate_required([:office_id, :name, :status])
    |> validate_length(:name, max: 255)
    |> validate_length(:code, max: 50)
    |> unique_constraint([:office_id, :name],
      error_key: :name,
      message: "この荷主名は既に登録されています"
    )
    |> assoc_constraint(:office)
  end
end
