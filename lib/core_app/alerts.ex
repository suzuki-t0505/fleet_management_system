defmodule CoreApp.Alerts do
  @moduledoc """
  The Alerts context.

  期限（車検・保険・法定点検・免許証）は車両と運転者の列に散らばっているため、
  6本のクエリを `union_all` で束ねた仮想的な一覧として扱います。

  通知の送信そのものは `CoreApp.Workers.DeadlineAlertWorker` と
  `CoreApp.Workers.AlertMailWorker` が行い、このContextは判定と記録を担当します。
  """

  import Ecto.Query, warn: false
  alias CoreApp.Repo

  alias CoreApp.Alerts.AlertNotification
  alias CoreApp.Alerts.Deadline

  alias CoreApp.Accounts.Scope
  alias CoreApp.Drivers.Driver
  alias CoreApp.Offices.Office
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Utils.Pagination
  alias CoreApp.Vehicles.Vehicle

  # 車両側の監視対象（functional-design 7.1）
  @vehicle_alerts [
    {:inspection, :inspection_expires_on},
    {:liability_insurance, :liability_insurance_expires_on},
    {:voluntary_insurance, :voluntary_insurance_expires_on},
    {:periodic_3m, :next_periodic_3m_on},
    {:periodic_12m, :next_periodic_12m_on}
  ]

  # 一覧・通知判定で走査する既定の日数
  @default_horizon_days 60

  # 絞り込みで選べる残日数
  @within_options [7, 30, 60]

  @doc """
  期限を残日数の昇順でページネーションして返します。

  廃車の車両と退職した運転者は対象外です。スコープが管理者以外の場合、所属拠点の
  対象のみを返します。

  ## params
  - `q` 検索ワード（車両番号・運転者氏名）
  - `within` 残日数（`7` / `30` / `60`、`overdue` で超過のみ）。既定は #{@default_horizon_days}
  - `alert_type` 期限種別
  - `office_id` 拠点（管理者のみ有効）
  - `page` / `page_size` ページネーション
  """
  def list_deadlines(%Scope{} = scope, params \\ %{}) do
    today = ConvertDatetime.today()

    page =
      today
      |> horizon(params["within"])
      |> deadlines_query()
      |> scoped(scope)
      |> filter_by_office(scope, params["office_id"])
      |> filter_by_alert_type(params["alert_type"])
      |> search(params["q"])
      |> order_by([d], asc: d.deadline_on, asc: d.target_name)
      |> Pagination.paginate(params, Repo)

    %{page | entries: Enum.map(page.entries, &Deadline.new(&1, today))}
  end

  @doc """
  ダッシュボード用に、超過と30日以内の件数を返します。

  ```elixir
  iex> count_deadlines_by_urgency(scope)
  %{overdue: 2, within_30: 5}
  ```
  """
  def count_deadlines_by_urgency(%Scope{} = scope) do
    today = ConvertDatetime.today()

    query =
      today
      |> Date.add(30)
      |> deadlines_query()
      |> scoped(scope)
      |> exclude(:select)

    %{
      overdue: query |> where([d], d.deadline_on < ^today) |> Repo.aggregate(:count),
      within_30: query |> where([d], d.deadline_on >= ^today) |> Repo.aggregate(:count)
    }
  end

  @doc """
  通知すべき期限をすべて返します。

  通知は拠点をまたぐ横断処理のため、スコープを取らずシステム権限で全拠点を走査します。
  残日数が通知対象の段階（60 / 30 / 7 / 0 日・超過7日ごと）に当たるものだけを返します。
  """
  def all_notifiable_deadlines(%Date{} = today \\ ConvertDatetime.today()) do
    today
    |> Date.add(@default_horizon_days)
    |> deadlines_query()
    |> Repo.all()
    |> Enum.map(&Deadline.new(&1, today))
    |> Enum.filter(&(notify_stage(&1) != nil))
  end

  @doc """
  期限に対して通知すべき段階を返します。通知しない日は `nil` を返します。
  """
  def notify_stage(%Deadline{days_left: days_left}), do: AlertNotification.stage_for(days_left)

  @doc """
  その段階の通知を既に送信済みかを返します。

  超過（`overdue`）は #{AlertNotification.overdue_interval_days()} 日ごとに送るため、
  直近 #{AlertNotification.overdue_interval_days()} 日以内に送信していれば送信済みとみなします。
  失敗（`failed`）は送信済みとみなさず、翌日の実行で再送します。
  """
  def notified?(%Deadline{} = deadline, stage, %Date{} = today \\ ConvertDatetime.today()) do
    deadline
    |> notification_query(stage)
    |> where([n], n.status == :sent)
    |> filter_recent(stage, today)
    |> Repo.exists?()
  end

  @doc """
  送信成功を通知ログに記録します。同じ段階・同じ日の記録は上書きします。
  """
  def record_sent(%Deadline{} = deadline, stage, %Date{} = today \\ ConvertDatetime.today()) do
    deadline
    |> log_attrs(stage, today)
    |> Map.merge(%{status: :sent, sent_at: DateTime.utc_now(:second), error_message: nil})
    |> upsert_notification()
  end

  @doc """
  送信失敗を通知ログに記録します。翌日の実行で再送の対象になります。
  """
  def record_failed(
        %Deadline{} = deadline,
        stage,
        reason,
        %Date{} = today \\ ConvertDatetime.today()
      ) do
    deadline
    |> log_attrs(stage, today)
    |> Map.merge(%{status: :failed, error_message: reason})
    |> upsert_notification()
  end

  @doc """
  対象に紐づく通知ログを新しい順に取得します。
  """
  def all_notifications_for(target_type, <<_::208>> = target_id) do
    AlertNotification
    |> where([n], n.target_type == ^target_type and n.target_id == ^target_id)
    |> order_by([n], desc: n.inserted_at)
    |> Repo.all()
  end

  @doc """
  絞り込みで選べる残日数の一覧を返します。
  """
  def within_options, do: @within_options

  defp upsert_notification(attrs) do
    %AlertNotification{}
    |> AlertNotification.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:status, :sent_at, :error_message, :updated_at]},
      conflict_target: [
        :target_type,
        :target_id,
        :alert_type,
        :deadline_on,
        :notify_stage,
        :notified_on
      ]
    )
  end

  defp log_attrs(%Deadline{} = deadline, stage, today) do
    %{
      target_type: deadline.target_type,
      target_id: deadline.target_id,
      alert_type: deadline.alert_type,
      deadline_on: deadline.deadline_on,
      notify_stage: stage,
      notified_on: today
    }
  end

  defp notification_query(%Deadline{} = deadline, stage) do
    where(
      AlertNotification,
      [n],
      n.target_type == ^deadline.target_type and n.target_id == ^deadline.target_id and
        n.alert_type == ^deadline.alert_type and n.deadline_on == ^deadline.deadline_on and
        n.notify_stage == ^stage
    )
  end

  # 超過は7日ごとに再送するため、直近の通知だけを見る。他の段階は一度送れば二度と送らない。
  defp filter_recent(query, :overdue, today) do
    since = Date.add(today, -AlertNotification.overdue_interval_days() + 1)

    where(query, [n], n.notified_on >= ^since)
  end

  defp filter_recent(query, _stage, _today), do: query

  # 6本のクエリを union_all で束ね、subquery として扱う。
  # 全件をメモリに読み込まずに並べ替え・ページネーションするため。
  defp deadlines_query(%Date{} = horizon) do
    union =
      @vehicle_alerts
      |> Enum.map(&vehicle_query(&1, horizon))
      |> Kernel.++([driver_query(horizon)])
      |> Enum.reduce(fn query, acc -> union_all(acc, ^query) end)

    from(d in subquery(union),
      join: o in Office,
      on: o.id == d.office_id,
      select_merge: %{office_name: o.name}
    )
  end

  defp vehicle_query({alert_type, column}, horizon) do
    from(v in Vehicle,
      where: v.status != :scrapped,
      where: not is_nil(field(v, ^column)) and field(v, ^column) <= ^horizon,
      select: %{
        target_type: type(^"vehicle", :string),
        target_id: v.id,
        target_name: v.plate_number,
        office_id: v.office_id,
        alert_type: type(^to_string(alert_type), :string),
        deadline_on: field(v, ^column)
      }
    )
  end

  defp driver_query(horizon) do
    from(d in Driver,
      where: d.employment_type != :retired,
      where: not is_nil(d.license_expires_on) and d.license_expires_on <= ^horizon,
      select: %{
        target_type: type(^"driver", :string),
        target_id: d.id,
        target_name: d.name,
        office_id: d.office_id,
        alert_type: type(^"license", :string),
        deadline_on: d.license_expires_on
      }
    )
  end

  defp horizon(today, "overdue"), do: Date.add(today, -1)

  defp horizon(today, within) when is_binary(within) and within != "" do
    case Integer.parse(within) do
      {days, _rest} when days >= 0 -> Date.add(today, days)
      _error -> Date.add(today, @default_horizon_days)
    end
  end

  defp horizon(today, _within), do: Date.add(today, @default_horizon_days)

  defp scoped(query, %Scope{role: :admin}), do: query

  defp scoped(query, %Scope{office_id: office_id}) do
    where(query, [d], d.office_id == ^office_id)
  end

  defp filter_by_office(query, %Scope{role: :admin}, office_id)
       when is_binary(office_id) and office_id != "" do
    where(query, [d], d.office_id == ^office_id)
  end

  defp filter_by_office(query, _scope, _office_id), do: query

  defp filter_by_alert_type(query, alert_type) when is_binary(alert_type) and alert_type != "" do
    where(query, [d], d.alert_type == ^alert_type)
  end

  defp filter_by_alert_type(query, _alert_type), do: query

  defp search(query, keyword) when is_binary(keyword) and keyword != "" do
    pattern = "%#{String.trim(keyword)}%"

    where(query, [d], ilike(d.target_name, ^pattern))
  end

  defp search(query, _keyword), do: query
end
