defmodule CoreApp.Incidents do
  @moduledoc """
  The Incidents context.

  報告（全ロール）から原因分析・改善策の登録・承認（運行管理者以上）までの状態遷移を扱います。
  全社共有された記録は拠点をまたいで参照できますが、他拠点から見る場合は氏名を伏せます（V-27）。
  """

  import Ecto.Query, warn: false
  alias CoreApp.Repo
  alias Ecto.Multi

  alias CoreApp.Incidents.Incident

  alias CoreApp.Accounts.Scope
  alias CoreApp.AuditLogs
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Utils.Pagination
  alias CoreApp.Vehicles.Vehicle

  @resource_type "incident"
  @preloads [:vehicle, :driver, :office, :reported_by_user, :approved_by_user]

  @doc """
  ページネーションに対応した事故・ヒヤリを取得します。発生日時の降順で返します。

  参照できる範囲はロールによって異なります。管理者は全件、運行管理者は自拠点と
  全社共有された記録、一般利用者は自分が報告した記録・自分が運転者の記録と
  全社共有された記録です。

  ## params
  - `q` 検索ワード（発生場所、発生状況）
  - `from` / `to` 発生日の期間
  - `category` 区分
  - `status` ステータス
  - `vehicle_id` 車両
  - `office_id` 拠点（管理者のみ有効）
  - `shared` `"true"` で全社共有された記録のみ
  - `page` / `page_size` ページネーション
  """
  def list_incidents(%Scope{} = scope, params \\ %{}) do
    Incident
    |> scoped(scope)
    |> filter_by_office(scope, params["office_id"])
    |> filter_by_category(params["category"])
    |> filter_by_status(params["status"])
    |> filter_by_vehicle(params["vehicle_id"])
    |> filter_by_shared(params["shared"])
    |> filter_by_period(params["from"], params["to"])
    |> search(params["q"])
    |> order_by([i], desc: i.occurred_at, desc: i.id)
    |> preload(^@preloads)
    |> Pagination.paginate(params, Repo)
  end

  @doc """
  IDで事故・ヒヤリを取得します。参照できない記録は `Ecto.NoResultsError` を発生させます。
  """
  def get_incident!(%Scope{} = scope, <<_::208>> = id) do
    Incident
    |> scoped(scope)
    |> preload(^@preloads)
    |> Repo.get!(id)
  end

  @doc """
  全社共有された記録を新しい順に取得します。ダッシュボードの新着表示に使います。
  """
  def all_shared_incidents(%Scope{} = scope, limit \\ 3) do
    Incident
    |> scoped(scope)
    |> where([i], i.shared_company_wide == true)
    |> order_by([i], desc: i.occurred_at, desc: i.id)
    |> limit(^limit)
    |> preload(^@preloads)
    |> Repo.all()
  end

  @doc """
  車両に紐づく事故・ヒヤリを新しい順に取得します。
  """
  def all_incidents_for_vehicle(%Scope{} = scope, <<_::208>> = vehicle_id, limit \\ 5) do
    Incident
    |> scoped(scope)
    |> where([i], i.vehicle_id == ^vehicle_id)
    |> order_by([i], desc: i.occurred_at, desc: i.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  運転者に紐づく事故・ヒヤリを新しい順に取得します。
  """
  def all_incidents_for_driver(%Scope{} = scope, <<_::208>> = driver_id, limit \\ 5) do
    Incident
    |> scoped(scope)
    |> where([i], i.driver_id == ^driver_id)
    |> order_by([i], desc: i.occurred_at, desc: i.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  未対応の車両不具合報告の件数を返します。

  `category = single`（車両単独・不具合）が `reported` のまま残っているものを数えます。
  """
  def count_open_vehicle_defects(%Scope{} = scope) do
    Incident
    |> scoped(scope)
    |> where([i], i.category == :single and i.status == :reported)
    |> Repo.aggregate(:count)
  end

  @doc """
  改善報告が完了していない事故・ヒヤリの件数を返します。
  """
  def count_open_incidents(%Scope{} = scope) do
    Incident
    |> scoped(scope)
    |> where([i], i.status != :closed)
    |> Repo.aggregate(:count)
  end

  @doc """
  事故・ヒヤリを報告します。監査ログを同一トランザクションで記録します。
  """
  def create_incident(%Scope{} = scope, attrs \\ %{}, opts \\ []) do
    changeset = change_incident(%Incident{}, scope, attrs)

    Multi.new()
    |> Multi.insert(:incident, changeset)
    |> AuditLogs.record_multi(
      :audit_log,
      scope,
      :create,
      &{@resource_type, &1.incident, changeset},
      opts
    )
    |> Repo.transaction()
    |> normalize_transaction()
  end

  @doc """
  報告内容を更新します。完了した記録と、他人の報告（一般利用者の場合）は更新できません。
  """
  def update_incident(%Scope{} = scope, %Incident{} = incident, attrs, opts \\ []) do
    with :ok <- ensure_editable(scope, incident) do
      changeset = change_incident(incident, scope, attrs)

      Multi.new()
      |> Multi.update(:incident, changeset)
      |> AuditLogs.record_multi(
        :audit_log,
        scope,
        :update,
        &{@resource_type, &1.incident, changeset},
        opts
      )
      |> Repo.transaction()
      |> normalize_transaction()
    end
  end

  @doc """
  報告内容のchangesetを取得します。拠点は選択した車両の配置拠点に従います。
  """
  def change_incident(%Incident{} = incident, %Scope{} = scope, attrs \\ %{}) do
    incident
    |> Incident.changeset(defaults(incident, scope, attrs))
    |> validate_office_scope(scope)
  end

  @doc """
  原因分析・改善策のchangesetを取得します。
  """
  def change_countermeasure(%Incident{} = incident, attrs \\ %{}) do
    Incident.countermeasure_changeset(incident, attrs)
  end

  @doc """
  原因分析を開始します。報告直後の記録にだけ行えます。
  """
  def start_analysis(%Scope{} = scope, %Incident{} = incident, opts \\ []) do
    with :ok <- ensure_manager(scope, incident),
         :ok <- ensure_status(incident, [:reported]) do
      transition(scope, Incident.start_analysis_changeset(incident), :update, opts)
    end
  end

  @doc """
  改善策を登録します。直接原因と対策内容が必須です（V-25）。
  """
  def report_countermeasure(%Scope{} = scope, %Incident{} = incident, attrs, opts \\ []) do
    with :ok <- ensure_manager(scope, incident),
         :ok <- ensure_status(incident, [:reported, :analyzing]) do
      transition(scope, Incident.report_countermeasure_changeset(incident, attrs), :update, opts)
    end
  end

  @doc """
  改善報告を承認します。報告者本人は承認できません（V-26）。
  """
  def approve_incident(%Scope{} = scope, %Incident{} = incident, opts \\ []) do
    with :ok <- ensure_manager(scope, incident),
         :ok <- ensure_status(incident, [:countermeasure_reported]),
         :ok <- ensure_not_reporter(scope, incident) do
      transition(scope, Incident.approve_changeset(incident, scope.user.id), :approve, opts)
    end
  end

  @doc """
  改善報告を差し戻し、分析中に戻します。
  """
  def reject_incident(%Scope{} = scope, %Incident{} = incident, opts \\ []) do
    with :ok <- ensure_manager(scope, incident),
         :ok <- ensure_status(incident, [:countermeasure_reported]),
         :ok <- ensure_not_reporter(scope, incident) do
      transition(scope, Incident.reject_changeset(incident), :reject, opts)
    end
  end

  @doc """
  全社共有の設定を変更します。管理者のみが行えます。
  """
  def share_incident(%Scope{role: :admin} = scope, %Incident{} = incident, shared?, opts \\ []) do
    transition(scope, Incident.share_changeset(incident, shared?), :share, opts)
  end

  @doc """
  スコープが報告内容を編集できるかを返します。
  """
  def editable?(_scope, %Incident{status: :closed}), do: false

  def editable?(%Scope{role: :admin}, %Incident{}), do: true

  def editable?(%Scope{role: :manager, office_id: office_id}, %Incident{} = incident) do
    incident.office_id == office_id
  end

  def editable?(%Scope{role: :member, user: user}, %Incident{status: :reported} = incident) do
    incident.reported_by_user_id == user.id
  end

  def editable?(_scope, _incident), do: false

  @doc """
  スコープが原因分析・改善策を登録できるかを返します。
  """
  def analyzable?(%Scope{} = scope, %Incident{} = incident) do
    ensure_manager(scope, incident) == :ok and incident.status != :closed
  end

  @doc """
  スコープが改善報告を承認・差戻しできるかを返します（V-26）。
  """
  def approvable?(%Scope{} = scope, %Incident{} = incident) do
    ensure_manager(scope, incident) == :ok and
      incident.status == :countermeasure_reported and
      ensure_not_reporter(scope, incident) == :ok
  end

  @doc """
  氏名を伏せて表示すべきかを返します（V-27）。

  全社共有された記録を**他拠点の利用者**が見る場合が対象です。全拠点に責任を持つ
  管理者は対象外とします。
  """
  def anonymize?(%Scope{role: :admin}, %Incident{}), do: false

  def anonymize?(%Scope{office_id: office_id}, %Incident{} = incident) do
    incident.shared_company_wide and incident.office_id != office_id
  end

  def anonymize?(_scope, _incident), do: false

  defp transition(scope, changeset, action, opts) do
    Multi.new()
    |> Multi.update(:incident, changeset)
    |> AuditLogs.record_multi(
      :audit_log,
      scope,
      action,
      &{@resource_type, &1.incident, changeset},
      opts
    )
    |> Repo.transaction()
    |> normalize_transaction()
  end

  defp scoped(query, %Scope{role: :admin}), do: query

  defp scoped(query, %Scope{role: :manager, office_id: office_id}) do
    where(query, [i], i.office_id == ^office_id or i.shared_company_wide == true)
  end

  defp scoped(query, %Scope{role: :member, user: user, driver_id: nil}) do
    where(query, [i], i.reported_by_user_id == ^user.id or i.shared_company_wide == true)
  end

  defp scoped(query, %Scope{role: :member, user: user, driver_id: driver_id}) do
    where(
      query,
      [i],
      i.reported_by_user_id == ^user.id or i.driver_id == ^driver_id or
        i.shared_company_wide == true
    )
  end

  # 記録の拠点は「車両の配置拠点」に従う。報告者の拠点ではない。
  defp defaults(incident, scope, attrs) do
    attrs
    |> convert_key("occurred_at")
    |> Map.put("reported_by_user_id", reported_by(incident, scope))
    |> put_office_id(incident, scope)
  end

  defp convert_key(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> Map.put(attrs, key, ConvertDatetime.parse_input(value))
      :error -> attrs
    end
  end

  defp put_office_id(attrs, incident, scope) do
    office_id =
      case vehicle_office_id(attrs["vehicle_id"] || attrs[:vehicle_id]) do
        nil -> incident.office_id || scope.office_id
        office_id -> office_id
      end

    Map.put(attrs, "office_id", office_id)
  end

  defp vehicle_office_id(<<_::208>> = vehicle_id) do
    Vehicle |> select([v], v.office_id) |> Repo.get(vehicle_id)
  end

  defp vehicle_office_id(_vehicle_id), do: nil

  defp reported_by(%Incident{reported_by_user_id: nil}, scope), do: scope.user.id
  defp reported_by(%Incident{reported_by_user_id: user_id}, _scope), do: user_id

  # 報告は全ロールが行えるが、一般利用者は自拠点の車両しか選べない。
  defp validate_office_scope(changeset, %Scope{role: :admin}), do: changeset

  defp validate_office_scope(changeset, %Scope{office_id: office_id}) do
    case Ecto.Changeset.get_field(changeset, :office_id) do
      nil -> changeset
      ^office_id -> changeset
      _other -> Ecto.Changeset.add_error(changeset, :vehicle_id, "は自拠点の車両を選択してください")
    end
  end

  defp ensure_editable(scope, incident) do
    if editable?(scope, incident), do: :ok, else: {:error, :unauthorized}
  end

  defp ensure_manager(%Scope{role: role} = scope, incident) when role in [:admin, :manager] do
    if role == :admin or incident.office_id == scope.office_id do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp ensure_manager(_scope, _incident), do: {:error, :unauthorized}

  # V-26: 承認は報告者本人以外が行う
  defp ensure_not_reporter(%Scope{user: user}, %Incident{reported_by_user_id: reporter_id}) do
    if user.id == reporter_id, do: {:error, :reporter}, else: :ok
  end

  defp ensure_status(%Incident{status: status}, allowed) do
    if status in allowed, do: :ok, else: {:error, :invalid_status}
  end

  defp filter_by_office(query, %Scope{role: :admin}, office_id)
       when is_binary(office_id) and office_id != "" do
    where(query, [i], i.office_id == ^office_id)
  end

  defp filter_by_office(query, _scope, _office_id), do: query

  defp filter_by_category(query, category) when is_binary(category) and category != "" do
    where(query, [i], i.category == ^category)
  end

  defp filter_by_category(query, _category), do: query

  defp filter_by_status(query, status) when is_binary(status) and status != "" do
    where(query, [i], i.status == ^status)
  end

  defp filter_by_status(query, _status), do: query

  defp filter_by_vehicle(query, vehicle_id) when is_binary(vehicle_id) and vehicle_id != "" do
    where(query, [i], i.vehicle_id == ^vehicle_id)
  end

  defp filter_by_vehicle(query, _vehicle_id), do: query

  defp filter_by_shared(query, "true"), do: where(query, [i], i.shared_company_wide == true)
  defp filter_by_shared(query, _shared), do: query

  defp filter_by_period(query, from, to) do
    query
    |> filter_from(parse_date(from))
    |> filter_to(parse_date(to))
  end

  defp filter_from(query, nil), do: query

  defp filter_from(query, from) do
    where(query, [i], i.occurred_at >= ^beginning_of_day(from))
  end

  defp filter_to(query, nil), do: query

  defp filter_to(query, to) do
    where(query, [i], i.occurred_at <= ^end_of_day(to))
  end

  # 画面から届く日付はJSTのため、その日のJSTの範囲をUTCに直して突き合わせる
  defp beginning_of_day(date) do
    date |> DateTime.new!(~T[00:00:00]) |> DateTime.add(-9, :hour)
  end

  defp end_of_day(date) do
    date |> DateTime.new!(~T[23:59:59]) |> DateTime.add(-9, :hour)
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

    where(query, [i], ilike(i.place, ^pattern) or ilike(i.description, ^pattern))
  end

  defp search(query, _keyword), do: query

  defp normalize_transaction({:ok, %{incident: incident}}), do: {:ok, incident}
  defp normalize_transaction({:error, :incident, changeset, _changes}), do: {:error, changeset}
end
