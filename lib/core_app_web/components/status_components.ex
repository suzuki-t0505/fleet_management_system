defmodule CoreAppWeb.StatusComponents do
  @moduledoc "ステータスと期限を表すバッジのコンポーネント"
  use Phoenix.Component

  alias CoreApp.Utils.ConvertDatetime

  @vehicle_statuses %{
    active: {"稼働中", "bg-accent-green"},
    maintenance: {"整備中", "bg-accent-teal"},
    idle: {"休車", "bg-ink-faint"},
    scrapped: {"廃車", "bg-ink-secondary"}
  }

  @report_statuses %{
    draft: {"下書き", "bg-ink-faint"},
    submitted: {"提出済み", "bg-accent-orange"},
    approved: {"承認済み", "bg-accent-green"},
    rejected: {"差戻し", "bg-accent-orange-deep"}
  }

  @user_statuses %{
    active: {"有効", "bg-accent-green"},
    inactive: {"無効", "bg-ink-secondary"},
    locked: {"ロック中", "bg-accent-orange-deep"}
  }

  @labels %{
    vehicle: @vehicle_statuses,
    operation_report: @report_statuses,
    user: @user_statuses
  }

  @doc """
  ステータスのバッジを表示します。

  `type` で対象のリソースを指定します（既定は車両）。
  """
  attr :status, :atom, required: true
  attr :type, :atom, default: :vehicle, values: [:vehicle, :operation_report, :user]

  def status_badge(assigns) do
    {label, color} = @labels |> Map.fetch!(assigns.type) |> Map.fetch!(assigns.status)
    assigns = assign(assigns, label: label, color: color)

    ~H"""
    <span class={["text-eyebrow inline-block rounded-full px-2 py-1 text-on-primary", @color]}>
      {@label}
    </span>
    """
  end

  @doc """
  期限日と残日数を表示します。期限が近い場合と超過した場合はバッジで強調します。
  """
  attr :date, :any, default: nil
  attr :class, :string, default: nil

  def deadline_badge(assigns) do
    assigns = assign(assigns, days: ConvertDatetime.days_until(assigns.date))

    ~H"""
    <span :if={is_nil(@date)} class={["text-body-sm text-ink-faint", @class]}>-</span>
    <span :if={@date} class={["inline-flex items-center gap-2", @class]}>
      <span class="text-body-sm text-ink-secondary">{format_date(@date)}</span>
      <span
        :if={badge_color(@days)}
        class={[
          "text-eyebrow inline-block rounded-full px-2 py-1 text-on-primary",
          badge_color(@days)
        ]}
      >
        {badge_label(@days)}
      </span>
    </span>
    """
  end

  @doc """
  日付を `YYYY/MM/DD` 形式で表示します。
  """
  def format_date(nil), do: "-"

  def format_date(%Date{} = date) do
    "#{date.year}/#{pad(date.month)}/#{pad(date.day)}"
  end

  @doc """
  日時を `YYYY/MM/DD HH:MM` 形式（JST）で表示します。
  """
  def format_datetime(nil), do: "-"

  def format_datetime(%DateTime{} = datetime) do
    jst = ConvertDatetime.to_jst(datetime)

    "#{format_date(DateTime.to_date(jst))} #{pad(jst.hour)}:#{pad(jst.minute)}"
  end

  defp badge_color(days) when days < 0, do: "bg-accent-orange-deep"
  defp badge_color(days) when days <= 7, do: "bg-accent-orange"
  defp badge_color(days) when days <= 30, do: "bg-accent-purple-deep"
  defp badge_color(_days), do: nil

  defp badge_label(days) when days < 0, do: "超過 #{abs(days)}日"
  defp badge_label(0), do: "本日"
  defp badge_label(days), do: "あと#{days}日"

  defp pad(number), do: String.pad_leading(to_string(number), 2, "0")
end
