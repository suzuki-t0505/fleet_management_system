defmodule CoreApp.Workers.DeadlineAlertWorker do
  @moduledoc """
  期限を毎日 07:00 (JST) に走査し、通知すべきものを `AlertMailWorker` にエンキューする
  ワーカーです。

  判定だけを行い、メールは送りません。ジョブ自体が最終的に失敗した場合は、全管理者に
  エラーを通知します（functional-design.md 7.2 手順7）。
  """
  use Oban.Worker, queue: :alerts, max_attempts: 5

  require Logger

  alias CoreApp.Accounts
  alias CoreApp.Alerts
  alias CoreApp.Alerts.AlertNotifier
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Workers.AlertMailWorker

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    today = ConvertDatetime.today()

    enqueued =
      today
      |> Alerts.all_notifiable_deadlines()
      |> Enum.map(&{&1, Alerts.notify_stage(&1)})
      |> Enum.reject(fn {deadline, stage} -> Alerts.notified?(deadline, stage, today) end)
      |> Enum.count(&enqueue(&1, today))

    Logger.info("期限アラートを#{enqueued}件エンキューしました")

    {:ok, enqueued}
  rescue
    exception ->
      notify_admins(job, exception)

      reraise exception, __STACKTRACE__
  end

  defp enqueue({deadline, stage}, today) do
    case deadline |> AlertMailWorker.build(stage, today) |> Oban.insert() do
      {:ok, _job} -> true
      {:error, _reason} -> false
    end
  end

  # 最終試行でも失敗した場合だけ通知する。リトライのたびにメールを送らないため。
  defp notify_admins(%Oban.Job{attempt: attempt, max_attempts: max_attempts}, exception)
       when attempt >= max_attempts do
    Accounts.all_admins() |> AlertNotifier.deliver_job_failure(Exception.message(exception))
  end

  defp notify_admins(_job, _exception), do: :ok
end
