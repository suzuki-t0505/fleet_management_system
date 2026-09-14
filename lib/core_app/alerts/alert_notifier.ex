defmodule CoreApp.Alerts.AlertNotifier do
  @moduledoc """
  期限アラートのメールを組み立てて送信するモジュールです。

  件名・本文の仕様は functional-design.md 7.3 に従います。
  詳細画面のURLを載せるため、ルーティング（`~p`）を参照します。
  """
  import Swoosh.Email

  use CoreAppWeb, :verified_routes

  alias CoreApp.Alerts.Deadline
  alias CoreApp.Mailer

  @doc """
  期限アラートを通知します。宛先は1通にまとめて送ります。

  ```elixir
  iex> deliver_deadline_alert(recipients, deadline)
  {:ok, %Swoosh.Email{}}
  ```
  """
  def deliver_deadline_alert([], %Deadline{}), do: {:error, :no_recipients}

  def deliver_deadline_alert(recipients, %Deadline{} = deadline) do
    deliver(recipients, subject(deadline), body(deadline))
  end

  @doc """
  期限判定ジョブの異常終了を管理者に通知します。
  """
  def deliver_job_failure([], _message), do: {:error, :no_recipients}

  def deliver_job_failure(recipients, message) do
    deliver(recipients, "[車両管理] 期限アラートの定時処理が失敗しました", """
    期限アラートの定時処理が異常終了しました。

    #{message}

    ログを確認し、必要であれば再実行してください。
    """)
  end

  defp deliver(recipients, subject, body) do
    email =
      new()
      |> to(Enum.map(recipients, &{&1.name, &1.email}))
      |> from({"CoreApp", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp subject(%Deadline{days_left: days_left} = deadline) when days_left < 0 do
    "[車両管理][超過] #{deadline.office_name} #{deadline.target_name} の#{label(deadline)}が期限切れです"
  end

  defp subject(%Deadline{} = deadline) do
    "[車両管理] #{deadline.office_name} #{deadline.target_name} の#{label(deadline)}が残り#{deadline.days_left}日です"
  end

  defp body(%Deadline{} = deadline) do
    """
    #{Deadline.target_type_label(deadline.target_type)}の#{label(deadline)}が近づいています。

    対象: #{deadline.target_name}（#{deadline.office_name}）
    期限種別: #{label(deadline)}
    期限日: #{Date.to_iso8601(deadline.deadline_on)}
    残日数: #{remaining(deadline)}

    詳細: #{detail_url(deadline)}
    """
  end

  defp remaining(%Deadline{days_left: days_left}) when days_left < 0 do
    "#{abs(days_left)}日超過"
  end

  defp remaining(%Deadline{days_left: days_left}), do: "あと#{days_left}日"

  defp label(%Deadline{alert_type: alert_type}), do: Deadline.alert_type_label(alert_type)

  defp detail_url(%Deadline{target_type: :vehicle, target_id: id}) do
    url(~p"/management/vehicles/#{id}")
  end

  defp detail_url(%Deadline{target_type: :driver, target_id: id}) do
    url(~p"/management/drivers/#{id}")
  end
end
