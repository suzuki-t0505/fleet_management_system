defmodule CoreApp.Offices.Office do
  @moduledoc false
  use CoreApp.Schema
  import Ecto.Changeset

  schema "offices" do
    field :code, :string
    field :name, :string
    field :postal_code, :string
    field :address, :string
    field :phone, :string
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(office, attrs) do
    office
    |> cast(attrs, [:code, :name, :postal_code, :address, :phone, :active])
    |> validate_required([:code, :name])
    |> validate_length(:code, max: 20)
    |> validate_length(:name, max: 100)
    |> validate_format(:postal_code, ~r/\A\d{3}-?\d{4}\z/, message: "は 000-0000 の形式で入力してください")
    |> unique_constraint(:code)
  end
end
