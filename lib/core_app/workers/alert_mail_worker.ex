defmodule CoreApp.Workers.AlertMailWorker do
  @moduledoc """
  期限アラートのメールを1通送るワーカーです。

  アラート1件＝1ジョブ＝1通とし、1通の失敗が他のアラートを止めないようにします。
  送信結果は `alert_notifications` に記録し、失敗は翌日の実行で再送の対象になります。
  """
  use Oban.Worker, queue: :mailers, max_attempts: 5, unique: [period: 72_000]

  alias CoreApp.Accounts
  alias CoreApp.Alerts
  alias CoreApp.Alerts.AlertNotifier
  alias CoreApp.Alerts.Deadline

  @doc """
  期限と段階から送信ジョブを組み立てます。
  """
  def build(%Deadline{} = deadline, stage, %Date{} = today) do
    deadline
    |> Deadline.to_args()
    |> Map.merge(%{
      "notify_stage" => to_string(stage),
      "notified_on" => Date.to_iso8601(today)
    })
    |> new()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    deadline = Deadline.from_args(args)
    stage = String.to_existing_atom(args["notify_stage"])
    today = Date.from_iso8601!(args["notified_on"])

    if Alerts.notified?(deadline, stage, today) do
      :ok
    else
      deliver(deadline, stage, today)
    end
  end

  defp deliver(deadline, stage, today) do
    deadline.office_id
    |> Accounts.all_alert_recipients()
    |> AlertNotifier.deliver_deadline_alert(deadline)
    |> record(deadline, stage, today)
  end

  defp record({:ok, _email}, deadline, stage, today) do
    {:ok, _notification} = Alerts.record_sent(deadline, stage, today)

    :ok
  end

  # 通知先がいない拠点は、再試行しても解決しないため記録して打ち切る
  defp record({:error, :no_recipients}, deadline, stage, today) do
    Alerts.record_failed(deadline, stage, "通知先の利用者が存在しません", today)

    {:cancel, :no_recipients}
  end

  defp record({:error, reason}, deadline, stage, today) do
    Alerts.record_failed(deadline, stage, inspect(reason), today)

    {:error, reason}
  end
end
