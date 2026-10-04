defmodule CoreApp.Dispatches do
  @moduledoc """
  The Dispatches context.

  配車（車両・ドライバー・荷主を配送に割り当てたもの）を管理します。配送明細（`Delivery`）は
  配車に従属する子エンティティのため、専用のContextを作らず、この Context が配車と同一
  トランザクションで保存します。

  受取金額は料金方式で決まります。

  - `:course_total`（コース一括）: コース料金 + 高速料金
  - `:per_delivery`（配送ごと）: 配送明細の配送料金の合計 + 高速料金
  """

  import Ecto.Query, warn: false
  alias CoreApp.Repo
  alias Ecto.Multi

  alias CoreApp.Dispatches.Board
  alias CoreApp.Dispatches.Delivery
  alias CoreApp.Dispatches.Dispatch
  alias CoreApp.Drivers.Driver
  alias CoreApp.Shippers.Shipper
  alias CoreApp.Vehicles.Vehicle

  alias CoreApp.Accounts.Scope
  alias CoreApp.AuditLogs
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Utils.Pagination

  @resource_type "dispatch"
  @preloads [:office, :shipper, :vehicle, :driver, :deliveries]

  @doc """
  ページネーションに対応した配車を取得します。配送開始日時の降順で返します。

  スコープが管理者以外の場合、所属拠点の配車のみを返します。一般利用者は自分に割り当てられた
  配車のみを返します。

  ## params
  - `q` 検索ワード（タイトル、荷主名、配送先）
  - `from` / `to` 配送開始日（JST）の期間
  - `shipper_id` / `vehicle_id` / `driver_id` 荷主・車両・ドライバー
  - `office_id` 拠点ID（管理者のみ有効）
  - `page` / `page_size` ページネーション
  """
  def list_dispatches(%Scope{} = scope, params \\ %{}) do
    Dispatch
    |> from(as: :dispatch)
    |> scoped(scope)
    |> filter_by_office(scope, params["office_id"])
    |> filter_by_id(:shipper_id, params["shipper_id"])
    |> filter_by_id(:vehicle_id, params["vehicle_id"])
    |> filter_by_id(:driver_id, params["driver_id"])
    |> filter_by_period(params["from"], params["to"])
    |> search(params["q"])
    |> order_by([dispatch: d], desc: d.started_at, desc: d.id)
    |> preload(^@preloads)
    |> Pagination.paginate(params, Repo)
  end

  @doc """
  指定したJSTの日付と時間が重なる配車をすべて取得します。配車表に使います。

  前日から続く配車・翌日へ続く配車を含みます。終了が0:00ちょうど、開始が翌0:00ちょうどの
  配車は含みません。ページネーションはしません（1日分のため）。スコープは `list_dispatches/2` と同じです。

  ## params
  - `office_id` 拠点ID（管理者のみ有効）
  """
  def list_dispatches_for_day(%Scope{} = scope, %Date{} = date, params \\ %{}) do
    {day_start, day_end} = Board.day_range(date)

    Dispatch
    |> from(as: :dispatch)
    |> scoped(scope)
    |> filter_by_office(scope, params["office_id"])
    |> where([dispatch: d], d.started_at < ^day_end and d.ended_at > ^day_start)
    |> order_by([dispatch: d], asc: d.started_at, asc: d.id)
    |> preload(^@preloads)
    |> Repo.all()
  end

  @doc """
  IDで配車を取得します。

  スコープの範囲外（他拠点、一般利用者の場合は他人の配車）は存在しないものとして扱い、
  `Ecto.NoResultsError` を発生させます。
  """
  def get_dispatch!(%Scope{} = scope, <<_::208>> = id) do
    Dispatch
    |> from(as: :dispatch)
    |> scoped(scope)
    |> preload(^@preloads)
    |> Repo.get!(id)
  end

  @doc """
  配車を登録し、監査ログを同一トランザクションで記録します。

  運行管理者以上のみ登録できます。それ以外は `{:error, :unauthorized}` を返します。
  """
  def create_dispatch(%Scope{} = scope, attrs \\ %{}, opts \\ []) do
    with :ok <- ensure_manager(scope) do
      changeset = change_dispatch(%Dispatch{deliveries: []}, scope, attrs)

      Multi.new()
      |> Multi.insert(:dispatch, changeset)
      |> AuditLogs.record_multi(
        :audit_log,
        scope,
        :create,
        &{@resource_type, &1.dispatch, changeset},
        opts
      )
      |> Repo.transaction()
      |> normalize_transaction()
    end
  end

  @doc """
  配車を更新し、監査ログを同一トランザクションで記録します。
  """
  def update_dispatch(%Scope{} = scope, %Dispatch{} = dispatch, attrs, opts \\ []) do
    with :ok <- ensure_manager(scope),
         :ok <- ensure_same_office(scope, dispatch) do
      changeset = change_dispatch(dispatch, scope, attrs)

      Multi.new()
      |> Multi.update(:dispatch, changeset)
      |> AuditLogs.record_multi(
        :audit_log,
        scope,
        :update,
        &{@resource_type, &1.dispatch, changeset},
        opts
      )
      |> Repo.transaction()
      |> normalize_transaction()
    end
  end

  @doc """
  配車のchangesetを取得します。

  拠点は選択した車両の配置拠点に従います。管理者以外は自拠点の車両しか選べません。
  荷主とドライバーは配車と同じ拠点のものに限ります（D-5）。
  """
  def change_dispatch(%Dispatch{} = dispatch, %Scope{} = scope, attrs \\ %{}) do
    dispatch
    |> Dispatch.changeset(defaults(dispatch, scope, attrs))
    |> validate_office_scope(scope)
    |> validate_same_office(:shipper_id, Shipper, "荷主")
    |> validate_same_office(:driver_id, Driver, "ドライバー")
    |> validate_shipper_active(dispatch)
  end

  @doc """
  受取金額の合計（円）を返します（D-2）。

  保存前の入力内容のプレビューに使えるよう、changesetも受け取ります。
  """
  def total_amount_yen(%Dispatch{} = dispatch), do: Dispatch.total_amount_yen(dispatch)

  def total_amount_yen(%Ecto.Changeset{} = changeset) do
    changeset |> Ecto.Changeset.apply_changes() |> Dispatch.total_amount_yen()
  end

  @doc """
  保存はできるが確認すべき事項を返します（D-4）。

  同じ車両・同じドライバーの配車が時間帯で重なっている場合に警告します。
  終了時刻と開始時刻がちょうど一致する場合は重なりとみなしません。
  """
  def warnings(%Scope{} = _scope, %Ecto.Changeset{} = changeset) do
    vehicle_id = Ecto.Changeset.get_field(changeset, :vehicle_id)
    driver_id = Ecto.Changeset.get_field(changeset, :driver_id)
    started_at = Ecto.Changeset.get_field(changeset, :started_at)
    ended_at = Ecto.Changeset.get_field(changeset, :ended_at)
    dispatch_id = Ecto.Changeset.get_field(changeset, :id)

    if is_nil(started_at) or is_nil(ended_at) do
      []
    else
      overlap = fn field, id ->
        not is_nil(id) and overlapping?(field, id, started_at, ended_at, dispatch_id)
      end

      []
      |> add_warning(overlap.(:vehicle_id, vehicle_id), "同じ車両で時間帯が重なる配車が既に登録されています。")
      |> add_warning(overlap.(:driver_id, driver_id), "同じドライバーで時間帯が重なる配車が既に登録されています。")
    end
  end

  defp add_warning(warnings, true, message), do: warnings ++ [message]
  defp add_warning(warnings, false, _message), do: warnings

  defp overlapping?(field, id, started_at, ended_at, dispatch_id) do
    Dispatch
    |> where([d], field(d, ^field) == ^id)
    |> where([d], d.started_at < ^ended_at and d.ended_at > ^started_at)
    |> exclude_self(dispatch_id)
    |> Repo.exists?()
  end

  defp exclude_self(query, nil), do: query
  defp exclude_self(query, dispatch_id), do: where(query, [d], d.id != ^dispatch_id)

  defp scoped(query, %Scope{role: :admin}), do: query

  defp scoped(query, %Scope{role: :manager, office_id: office_id}) do
    where(query, [dispatch: d], d.office_id == ^office_id)
  end

  defp scoped(query, %Scope{role: :member, driver_id: nil}) do
    where(query, [dispatch: d], false)
  end

  defp scoped(query, %Scope{role: :member, driver_id: driver_id}) do
    where(query, [dispatch: d], d.driver_id == ^driver_id)
  end

  defp ensure_manager(%Scope{role: role}) when role in [:admin, :manager], do: :ok
  defp ensure_manager(_scope), do: {:error, :unauthorized}

  defp ensure_same_office(%Scope{role: :admin}, _dispatch), do: :ok

  defp ensure_same_office(%Scope{office_id: office_id}, %Dispatch{office_id: office_id}), do: :ok

  defp ensure_same_office(_scope, _dispatch), do: {:error, :unauthorized}

  # フォーム（datetime-local）から届く日時はJSTのため、UTCに変換してからcastする。
  defp defaults(dispatch, scope, attrs) do
    attrs
    |> convert_key("started_at")
    |> convert_key("ended_at")
    |> convert_deliveries()
    |> Map.put("created_by_user_id", created_by(dispatch, scope))
    |> put_office_id(dispatch, scope)
  end

  defp convert_key(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> Map.put(attrs, key, ConvertDatetime.parse_input(value))
      :error -> attrs
    end
  end

  # 配送明細の荷積み・荷降ろし日時も、フォームからはJSTで届く。
  defp convert_deliveries(attrs) do
    case Map.fetch(attrs, "deliveries") do
      {:ok, deliveries} when is_map(deliveries) ->
        Map.put(
          attrs,
          "deliveries",
          Map.new(deliveries, fn {index, delivery} ->
            {index, delivery |> convert_key("loading_at") |> convert_key("unloading_at")}
          end)
        )

      _other ->
        attrs
    end
  end

  # 配車の拠点は「車両の配置拠点」に従う。登録者の拠点ではない。
  defp put_office_id(attrs, dispatch, scope) do
    office_id =
      case vehicle_office_id(attrs["vehicle_id"] || attrs[:vehicle_id]) do
        nil -> dispatch.office_id || scope.office_id
        office_id -> office_id
      end

    Map.put(attrs, "office_id", office_id)
  end

  defp vehicle_office_id(<<_::208>> = vehicle_id) do
    Vehicle |> select([v], v.office_id) |> Repo.get(vehicle_id)
  end

  defp vehicle_office_id(_vehicle_id), do: nil

  defp created_by(%Dispatch{created_by_user_id: nil}, scope), do: scope.user.id
  defp created_by(%Dispatch{created_by_user_id: user_id}, _scope), do: user_id

  # 管理者以外は自拠点の車両でしか配車を作れない
  defp validate_office_scope(changeset, %Scope{role: :admin}), do: changeset

  defp validate_office_scope(changeset, %Scope{office_id: office_id}) do
    case Ecto.Changeset.get_field(changeset, :office_id) do
      nil -> changeset
      ^office_id -> changeset
      _other -> Ecto.Changeset.add_error(changeset, :vehicle_id, "は自拠点の車両を選択してください")
    end
  end

  # D-5: 荷主・ドライバーは配車（車両）と同じ拠点のものに限る
  defp validate_same_office(changeset, field, schema, label) do
    id = Ecto.Changeset.get_field(changeset, field)
    office_id = Ecto.Changeset.get_field(changeset, :office_id)

    with <<_::208>> <- id,
         false <- is_nil(office_id),
         found when not is_nil(found) <- Repo.get(schema, id),
         true <- found.office_id != office_id do
      Ecto.Changeset.add_error(changeset, field, "は配車と同じ拠点の#{label}を選択してください")
    else
      _other -> changeset
    end
  end

  # D-6: 無効な荷主は新たに選べない。既に紐付いている荷主のままなら変更しない。
  defp validate_shipper_active(changeset, %Dispatch{} = dispatch) do
    shipper_id = Ecto.Changeset.get_field(changeset, :shipper_id)

    with <<_::208>> <- shipper_id,
         true <- shipper_id != dispatch.shipper_id,
         %Shipper{status: :inactive} <- Repo.get(Shipper, shipper_id) do
      Ecto.Changeset.add_error(changeset, :shipper_id, "は無効なため選択できません")
    else
      _other -> changeset
    end
  end

  defp filter_by_office(query, %Scope{role: :admin}, office_id)
       when is_binary(office_id) and office_id != "" do
    where(query, [dispatch: d], d.office_id == ^office_id)
  end

  defp filter_by_office(query, _scope, _office_id), do: query

  defp filter_by_id(query, field, id) when is_binary(id) and id != "" do
    where(query, [dispatch: d], field(d, ^field) == ^id)
  end

  defp filter_by_id(query, _field, _id), do: query

  # 期間は配送開始日（JST）で絞り込む。JSTの日付の範囲をUTCの日時に直して比較する。
  defp filter_by_period(query, from, to) do
    query
    |> filter_from(parse_date(from))
    |> filter_to(parse_date(to))
  end

  defp filter_from(query, nil), do: query

  defp filter_from(query, from) do
    where(query, [dispatch: d], d.started_at >= ^start_of_day_utc(from))
  end

  defp filter_to(query, nil), do: query

  defp filter_to(query, to) do
    where(query, [dispatch: d], d.started_at < ^start_of_day_utc(Date.add(to, 1)))
  end

  defp start_of_day_utc(%Date{} = date) do
    date
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.add(-9, :hour)
  end

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

    destinations =
      from(del in Delivery,
        where: del.dispatch_id == parent_as(:dispatch).id and ilike(del.destination, ^pattern)
      )

    query
    |> join(:inner, [dispatch: d], s in assoc(d, :shipper), as: :shipper)
    |> where(
      [dispatch: d, shipper: s],
      ilike(d.title, ^pattern) or ilike(s.name, ^pattern) or exists(destinations)
    )
  end

  defp search(query, _keyword), do: query

  defp normalize_transaction({:ok, %{dispatch: dispatch}}) do
    {:ok, Repo.preload(dispatch, @preloads, force: true)}
  end

  defp normalize_transaction({:error, :dispatch, changeset, _changes}), do: {:error, changeset}
end
