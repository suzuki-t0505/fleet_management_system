defmodule CoreApp.Incidents.Incident do
  @moduledoc false
  use CoreApp.Schema
  import Ecto.Changeset

  alias CoreApp.Accounts.User
  alias CoreApp.Drivers.Driver
  alias CoreApp.Offices.Office
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Vehicles.Vehicle

  @categories ~w(injury property single near_miss)a
  @weathers ~w(clear cloudy rain snow fog other)a
  @statuses ~w(reported analyzing countermeasure_reported closed)a

  schema "incidents" do
    field :occurred_at, :utc_datetime
    field :category, Ecto.Enum, values: @categories
    field :place, :string
    field :weather, Ecto.Enum, values: @weathers
    field :description, :string
    field :counterpart, :string
    field :damage, :string
    field :police_reported, :boolean, default: false

    field :status, Ecto.Enum, values: @statuses, default: :reported
    field :shared_company_wide, :boolean, default: false

    field :direct_cause, :string
    field :background_factor, :string
    field :countermeasure, :string
    field :countermeasure_due_on, :date
    field :countermeasure_owner, :string

    field :approved_at, :utc_datetime

    belongs_to(:office, Office)
    belongs_to(:vehicle, Vehicle)
    belongs_to(:driver, Driver)
    belongs_to(:reported_by_user, User)
    belongs_to(:approved_by_user, User)

    timestamps(type: :utc_datetime)
  end

  @doc """
  事故・ヒヤリの区分の一覧を返します。
  """
  def categories, do: @categories

  @doc """
  天候の一覧を返します。
  """
  def weathers, do: @weathers

  @doc """
  ステータスの一覧を返します。
  """
  def statuses, do: @statuses

  @doc """
  報告内容のchangesetです。
  """
  def changeset(incident, attrs) do
    incident
    |> cast(attrs, [
      :office_id,
      :vehicle_id,
      :driver_id,
      :reported_by_user_id,
      :occurred_at,
      :category,
      :place,
      :weather,
      :description,
      :counterpart,
      :damage,
      :police_reported
    ])
    |> validate_required([
      :office_id,
      :vehicle_id,
      :reported_by_user_id,
      :occurred_at,
      :category,
      :place,
      :weather,
      :description
    ])
    |> validate_length(:place, max: 255)
    |> validate_occurred_at()
    |> assoc_constraint(:office)
    |> assoc_constraint(:vehicle)
    |> assoc_constraint(:driver)
  end

  @doc """
  原因分析・改善策のchangesetです。

  ## options
  - `complete` 改善策の登録（`countermeasure_reported` への遷移）かどうか。
    `true` のとき直接原因と対策内容を必須にします（V-25）。
  """
  def countermeasure_changeset(incident, attrs, opts \\ []) do
    incident
    |> cast(attrs, [
      :direct_cause,
      :background_factor,
      :countermeasure,
      :countermeasure_due_on,
      :countermeasure_owner
    ])
    |> validate_length(:countermeasure_owner, max: 100)
    |> validate_countermeasure(Keyword.get(opts, :complete, false))
  end

  @doc """
  原因分析を開始するchangesetです。
  """
  def start_analysis_changeset(incident), do: change(incident, status: :analyzing)

  @doc """
  改善策を登録するchangesetです。直接原因と対策内容が必須です（V-25）。
  """
  def report_countermeasure_changeset(incident, attrs) do
    incident
    |> countermeasure_changeset(attrs, complete: true)
    |> put_change(:status, :countermeasure_reported)
  end

  @doc """
  改善報告を承認するchangesetです。
  """
  def approve_changeset(incident, approver_id) do
    change(incident,
      status: :closed,
      approved_at: DateTime.utc_now(:second),
      approved_by_user_id: approver_id
    )
  end

  @doc """
  改善報告を差し戻すchangesetです。分析中に戻します。
  """
  def reject_changeset(incident) do
    change(incident, status: :analyzing, approved_at: nil, approved_by_user_id: nil)
  end

  @doc """
  全社共有の設定を変更するchangesetです。
  """
  def share_changeset(incident, shared?) do
    change(incident, shared_company_wide: shared?)
  end

  # V-24: 発生日時に未来日時は登録できない
  defp validate_occurred_at(changeset) do
    validate_change(changeset, :occurred_at, fn :occurred_at, value ->
      if DateTime.after?(value, DateTime.utc_now()) do
        [occurred_at: "に未来の日時は入力できません"]
      else
        []
      end
    end)
  end

  # V-25: 改善策を登録するには直接原因と対策内容が要る
  defp validate_countermeasure(changeset, false), do: changeset

  defp validate_countermeasure(changeset, true) do
    changeset
    |> validate_required([:direct_cause], message: "を入力してください")
    |> validate_required([:countermeasure], message: "を入力してください")
    |> validate_due_on()
  end

  defp validate_due_on(changeset) do
    validate_change(changeset, :countermeasure_due_on, fn :countermeasure_due_on, value ->
      if Date.before?(value, ConvertDatetime.today()) do
        [countermeasure_due_on: "に過去の日付は入力できません"]
      else
        []
      end
    end)
  end
end
