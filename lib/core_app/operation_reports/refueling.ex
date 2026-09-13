defmodule CoreApp.OperationReports.Refueling do
  @moduledoc false
  use CoreApp.Schema
  import Ecto.Changeset

  schema "refuelings" do
    field :refueled_at, :utc_datetime
    field :liters, :decimal
    field :amount_yen, :integer
    field :odometer, :integer

    field :operation_report_id, Ecto.ULID

    timestamps(type: :utc_datetime)
  end

  def changeset(refueling, attrs) do
    refueling
    |> cast(attrs, [:refueled_at, :liters, :amount_yen, :odometer])
    |> validate_required([:refueled_at, :liters])
    |> validate_number(:liters, greater_than: 0)
    |> validate_number(:amount_yen, greater_than_or_equal_to: 0)
    |> validate_number(:odometer, greater_than_or_equal_to: 0)
  end

  @doc """
  給油日時が運行時間の範囲内かを検証します（追加2）。

  親である運行日報の出発・帰着日時と突き合わせるため、日報側から呼び出します。
  """
  def validate_within_operation(changeset, nil, _returned_at), do: changeset
  def validate_within_operation(changeset, _departed_at, nil), do: changeset

  def validate_within_operation(changeset, departed_at, returned_at) do
    validate_change(changeset, :refueled_at, fn :refueled_at, value ->
      cond do
        DateTime.before?(value, departed_at) -> [refueled_at: "は出発日時より後にしてください"]
        DateTime.after?(value, returned_at) -> [refueled_at: "は帰着日時より前にしてください"]
        true -> []
      end
    end)
  end
end
