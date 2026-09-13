defmodule CoreApp.Maintenances do
  @moduledoc """
  The Maintenances context.

  点検整備記録の登録にあわせて、車両台帳の次回期限（車検満了日・法定点検の予定日）を
  同一トランザクションで更新します（V-20・V-21）。
  """

  import Ecto.Query, warn: false
  alias CoreApp.Repo
  alias Ecto.Multi

  alias CoreApp.Maintenances.Maintenance

  alias CoreApp.Accounts.Scope
  alias CoreApp.AuditLogs
  alias CoreApp.Vehicles.Vehicle
  alias CoreApp.Utils.Pagination

  @resource_type "maintenance"
  @preloads [:vehicle, :office, :created_by_user]

  @doc """
  ページネーションに対応した点検整備記録を取得します。実施日の降順で返します。

  スコープが管理者以外の場合、所属拠点の記録のみを返します。

  ## params
  - `q` 検索ワード（車両番号、実施業者）
  - `from` / `to` 実施日の期間
  - `vehicle_id` 車両
  - `category` 区分
  - `office_id` 拠点（管理者のみ有効）
  - `page` / `page_size` ページネーション
  """
  def list_maintenances(%Scope{} = scope, params \\ %{}) do
    Maintenance
    |> scoped(scope)
    |> filter_by_office(scope, params["office_id"])
    |> filter_by_vehicle(params["vehicle_id"])
    |> filter_by_category(params["category"])
    |> filter_by_period(params["from"], params["to"])
    |> search(params["q"])
    |> order_by([m], desc: m.performed_on, desc: m.inserted_at)
    |> preload(^@preloads)
    |> Pagination.paginate(params, Repo)
  end

  @doc """
  車両の点検整備履歴を実施日の降順で取得します。車両詳細の履歴表示に使います。
  """
  def all_maintenances_for_vehicle(%Scope{} = scope, <<_::208>> = vehicle_id, limit \\ 5) do
    Maintenance
    |> scoped(scope)
    |> where([m], m.vehicle_id == ^vehicle_id)
    |> order_by([m], desc: m.performed_on, desc: m.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  IDで点検整備記録を取得します。

  スコープの範囲外（他拠点）の記録は存在しないものとして扱い、`Ecto.NoResultsError` を
  発生させます。
  """
  def get_maintenance!(%Scope{} = scope, <<_::208>> = id) do
    Maintenance
    |> scoped(scope)
    |> preload(^@preloads)
    |> Repo.get!(id)
  end

  @doc """
  区分ごとの記録件数を返します。
  """
  def count_maintenances_by_category(%Scope{} = scope) do
    Maintenance
    |> scoped(scope)
    |> group_by([m], m.category)
    |> select([m], {m.category, count(m.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  点検整備記録を登録します。

  車検・法定点検の場合は車両の次回期限を更新し、監査ログとあわせて同一トランザクションで
  保存します（V-20・V-21）。

  ```elixir
  iex> create_maintenance(scope, %{"vehicle_id" => id, "category" => "inspection", ...})
  {:ok, %Maintenance{}}
  ```
  """
  def create_maintenance(%Scope{} = scope, attrs \\ %{}, opts \\ []) do
    changeset = change_maintenance(%Maintenance{}, scope, attrs)

    Multi.new()
    |> Multi.insert(:maintenance, changeset)
    |> Multi.run(:vehicle, &update_vehicle_deadline/2)
    |> AuditLogs.record_multi(
      :audit_log,
      scope,
      :create,
      &{@resource_type, &1.maintenance, changeset},
      opts
    )
    |> Repo.transaction()
    |> normalize_transaction()
  end

  @doc """
  点検整備記録を更新します。車両の次回期限も登録時と同じ規則で更新します。
  """
  def update_maintenance(%Scope{} = scope, %Maintenance{} = maintenance, attrs, opts \\ []) do
    changeset = change_maintenance(maintenance, scope, attrs)

    Multi.new()
    |> Multi.update(:maintenance, changeset)
    |> Multi.run(:vehicle, &update_vehicle_deadline/2)
    |> AuditLogs.record_multi(
      :audit_log,
      scope,
      :update,
      &{@resource_type, &1.maintenance, changeset},
      opts
    )
    |> Repo.transaction()
    |> normalize_transaction()
  end

  @doc """
  点検整備記録のchangesetを取得します。

  拠点は選択した車両の配置拠点に従います。管理者以外は自拠点の車両しか選べません。
  """
  def change_maintenance(%Maintenance{} = maintenance, %Scope{} = scope, attrs \\ %{}) do
    maintenance
    |> Maintenance.changeset(defaults(maintenance, scope, attrs))
    |> validate_office_scope(scope)
  end

  @doc """
  保存はできるが確認すべき事項を返します（V-23）。

  車両の最終オドメーターとの突き合わせが必要なため、changesetではなくここで判定します。
  """
  def warnings(%Scope{} = _scope, %Ecto.Changeset{} = changeset) do
    vehicle_id = Ecto.Changeset.get_field(changeset, :vehicle_id)
    odometer = Ecto.Changeset.get_field(changeset, :odometer)

    with false <- is_nil(vehicle_id) or is_nil(odometer),
         latest when is_integer(latest) <- latest_odometer(vehicle_id),
         true <- odometer < latest do
      ["車両の最終オドメーター #{latest} km を下回っています。入力値を確認してください。"]
    else
      _other -> []
    end
  end

  # V-20・V-21: 区分に対応する車両の期限カラムを、記録の次回予定日で更新する。
  # 対応する区分でない場合は車両を変更しない。
  defp update_vehicle_deadline(repo, %{maintenance: maintenance}) do
    case Maintenance.deadline_field(maintenance.category) do
      nil ->
        {:ok, nil}

      field ->
        Vehicle
        |> repo.get!(maintenance.vehicle_id)
        |> Ecto.Changeset.change(%{field => maintenance.next_scheduled_on})
        |> repo.update()
    end
  end

  defp latest_odometer(vehicle_id) do
    Vehicle |> select([v], v.latest_odometer) |> Repo.get(vehicle_id)
  end

  defp scoped(query, %Scope{role: :admin}), do: query

  defp scoped(query, %Scope{office_id: office_id}) do
    where(query, [m], m.office_id == ^office_id)
  end

  # 記録の拠点は「車両の配置拠点」に従う。登録者の拠点ではない。
  defp defaults(maintenance, scope, attrs) do
    attrs
    |> Map.put("created_by_user_id", created_by(maintenance, scope))
    |> put_office_id(maintenance, scope)
  end

  defp put_office_id(attrs, maintenance, scope) do
    office_id =
      case vehicle_office_id(attrs["vehicle_id"] || attrs[:vehicle_id]) do
        nil -> maintenance.office_id || scope.office_id
        office_id -> office_id
      end

    Map.put(attrs, "office_id", office_id)
  end

  defp vehicle_office_id(<<_::208>> = vehicle_id) do
    Vehicle |> select([v], v.office_id) |> Repo.get(vehicle_id)
  end

  defp vehicle_office_id(_vehicle_id), do: nil

  defp created_by(%Maintenance{created_by_user_id: nil}, scope), do: scope.user.id
  defp created_by(%Maintenance{created_by_user_id: user_id}, _scope), do: user_id

  defp validate_office_scope(changeset, %Scope{role: :admin}), do: changeset

  defp validate_office_scope(changeset, %Scope{office_id: office_id}) do
    case Ecto.Changeset.get_field(changeset, :office_id) do
      nil -> changeset
      ^office_id -> changeset
      _other -> Ecto.Changeset.add_error(changeset, :vehicle_id, "は自拠点の車両を選択してください")
    end
  end

  defp filter_by_office(query, %Scope{role: :admin}, office_id)
       when is_binary(office_id) and office_id != "" do
    where(query, [m], m.office_id == ^office_id)
  end

  defp filter_by_office(query, _scope, _office_id), do: query

  defp filter_by_vehicle(query, vehicle_id) when is_binary(vehicle_id) and vehicle_id != "" do
    where(query, [m], m.vehicle_id == ^vehicle_id)
  end

  defp filter_by_vehicle(query, _vehicle_id), do: query

  defp filter_by_category(query, category) when is_binary(category) and category != "" do
    where(query, [m], m.category == ^category)
  end

  defp filter_by_category(query, _category), do: query

  defp filter_by_period(query, from, to) do
    query
    |> filter_from(parse_date(from))
    |> filter_to(parse_date(to))
  end

  defp filter_from(query, nil), do: query
  defp filter_from(query, from), do: where(query, [m], m.performed_on >= ^from)

  defp filter_to(query, nil), do: query
  defp filter_to(query, to), do: where(query, [m], m.performed_on <= ^to)

  defp parse_date(value) when is_binary(value) and value != "" do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _error -> nil
    end
  end

  defp parse_date(%Date{} = date), do: date
  defp parse_date(_value), do: nil

  defp search(query, keyword) when is_binary(keyword) and keyword != "" do
    pattern = "%#{String.trim(keyword)}%"

    query
    |> join(:inner, [m], v in assoc(m, :vehicle), as: :vehicle)
    |> where([m, vehicle: v], ilike(v.plate_number, ^pattern) or ilike(m.vendor, ^pattern))
  end

  defp search(query, _keyword), do: query

  defp normalize_transaction({:ok, %{maintenance: maintenance}}), do: {:ok, maintenance}

  defp normalize_transaction({:error, :maintenance, changeset, _changes}), do: {:error, changeset}
end
