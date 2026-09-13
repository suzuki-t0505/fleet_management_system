defmodule CoreApp.Vehicles do
  @moduledoc """
  The Vehicles context.
  """

  import Ecto.Query, warn: false
  alias CoreApp.Repo
  alias Ecto.Multi

  alias CoreApp.Vehicles.Vehicle

  alias CoreApp.Accounts.Scope
  alias CoreApp.AuditLogs
  alias CoreApp.Utils.Pagination

  @resource_type "vehicle"

  @doc """
  ページネーションに対応した車両を取得します。車両番号の昇順で返します。

  スコープが管理者以外の場合、所属拠点の車両のみを返します。

  ## params
  - `q` 検索ワード（車両番号、車名）
  - `office_id` 拠点ID（管理者のみ有効）
  - `status` ステータス。未指定時は廃車を除外し、`all` を指定すると廃車を含む
  - `vehicle_class` 車種区分
  - `page` ページ番号
  - `page_size` 取得するデータ数
  """
  def list_vehicles(%Scope{} = scope, params \\ %{}) do
    Vehicle
    |> scoped(scope)
    |> filter_by_office(scope, params["office_id"])
    |> filter_by_status(params["status"])
    |> filter_by_vehicle_class(params["vehicle_class"])
    |> search(params["q"])
    |> order_by([v], asc: v.plate_number)
    |> preload(:office)
    |> Pagination.paginate(params, Repo)
  end

  @doc """
  他機能の選択肢に出せる車両（廃車を除く）をすべて取得します。
  """
  def all_selectable_vehicles(%Scope{} = scope) do
    Vehicle
    |> scoped(scope)
    |> where([v], v.status != :scrapped)
    |> order_by([v], asc: v.plate_number)
    |> Repo.all()
  end

  @doc """
  IDで車両を取得します。

  スコープの範囲外（他拠点）の車両は存在しないものとして扱い、`Ecto.NoResultsError` を
  発生させます。他拠点に何が存在するかを推測させないためです。
  """
  def get_vehicle!(%Scope{} = scope, <<_::208>> = id) do
    Vehicle
    |> scoped(scope)
    |> preload(:office)
    |> Repo.get!(id)
  end

  @doc """
  ステータスごとの車両台数を返します。廃車は含みません。
  """
  def count_vehicles_by_status(%Scope{} = scope) do
    Vehicle
    |> scoped(scope)
    |> where([v], v.status != :scrapped)
    |> group_by([v], v.status)
    |> select([v], {v.status, count(v.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  車両を登録し、監査ログを同一トランザクションで記録します。

  ```elixir
  iex> create_vehicle(scope, %{"plate_number" => "品川100あ1234", ...})
  {:ok, %Vehicle{}}
  ```
  """
  def create_vehicle(%Scope{} = scope, attrs \\ %{}, opts \\ []) do
    changeset = Vehicle.changeset(%Vehicle{}, put_office_id(scope, attrs))

    Multi.new()
    |> Multi.insert(:vehicle, changeset)
    |> AuditLogs.record_multi(
      :audit_log,
      scope,
      :create,
      &{@resource_type, &1.vehicle, changeset},
      opts
    )
    |> Repo.transaction()
    |> normalize_transaction()
  end

  @doc """
  車両を更新し、監査ログを同一トランザクションで記録します。

  ステータスの変更もこの関数で行います。車両の物理削除は提供しません。
  """
  def update_vehicle(%Scope{} = scope, %Vehicle{} = vehicle, attrs, opts \\ []) do
    changeset = Vehicle.changeset(vehicle, put_office_id(scope, attrs))

    Multi.new()
    |> Multi.update(:vehicle, changeset)
    |> AuditLogs.record_multi(
      :audit_log,
      scope,
      :update,
      &{@resource_type, &1.vehicle, changeset},
      opts
    )
    |> Repo.transaction()
    |> normalize_transaction()
  end

  @doc """
  車両のchangesetを取得します。
  """
  def change_vehicle(%Vehicle{} = vehicle, attrs \\ %{}) do
    Vehicle.changeset(vehicle, attrs)
  end

  defp scoped(query, %Scope{role: :admin}), do: query

  defp scoped(query, %Scope{office_id: office_id}) do
    where(query, [v], v.office_id == ^office_id)
  end

  # 運行管理者・一般利用者は自拠点に強制する。管理者のみ拠点を指定できる。
  defp put_office_id(%Scope{role: :admin}, attrs), do: attrs

  defp put_office_id(%Scope{office_id: office_id}, attrs) do
    Map.put(attrs, "office_id", office_id)
  end

  defp filter_by_office(query, %Scope{role: :admin}, office_id)
       when is_binary(office_id) and office_id != "" do
    where(query, [v], v.office_id == ^office_id)
  end

  defp filter_by_office(query, _scope, _office_id), do: query

  defp filter_by_status(query, "all"), do: query

  defp filter_by_status(query, status) when is_binary(status) and status != "" do
    where(query, [v], v.status == ^status)
  end

  defp filter_by_status(query, _status), do: where(query, [v], v.status != :scrapped)

  defp filter_by_vehicle_class(query, vehicle_class)
       when is_binary(vehicle_class) and vehicle_class != "" do
    where(query, [v], v.vehicle_class == ^vehicle_class)
  end

  defp filter_by_vehicle_class(query, _vehicle_class), do: query

  defp search(query, keyword) when is_binary(keyword) and keyword != "" do
    pattern = "%#{String.trim(keyword)}%"

    where(query, [v], ilike(v.plate_number, ^pattern) or ilike(v.model_name, ^pattern))
  end

  defp search(query, _keyword), do: query

  defp normalize_transaction({:ok, %{vehicle: vehicle}}), do: {:ok, vehicle}
  defp normalize_transaction({:error, :vehicle, changeset, _changes}), do: {:error, changeset}
end
