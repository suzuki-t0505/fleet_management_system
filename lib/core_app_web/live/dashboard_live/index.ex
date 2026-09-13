defmodule CoreAppWeb.DashboardLive.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.OperationReports

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(page_title: "ダッシュボード")
     |> assign(report_counts: OperationReports.count_reports_by_status(scope))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="space-y-6">
        <section class="rounded-lg border border-hairline bg-surface p-6">
          <p class="text-eyebrow text-ink-muted">ようこそ</p>
          <p class="text-heading-2 mt-1">{@current_scope.user.name} さん</p>
          <p class="text-body-sm text-ink-muted mt-2">
            {role_label(@current_scope.role)} ／ {@current_scope.user.office.name}
          </p>
        </section>

        <div :if={!Scope.manager?(@current_scope)} class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <.count_card
            label="未提出の日報"
            count={count(@report_counts, :draft)}
            path={~p"/operation_reports?#{%{"status" => "draft"}}"}
            tone={if count(@report_counts, :draft) > 0, do: "text-accent-orange", else: "text-ink"}
          />
          <.count_card
            label="差し戻された日報"
            count={count(@report_counts, :rejected)}
            path={~p"/operation_reports?#{%{"status" => "rejected"}}"}
            tone={
              if count(@report_counts, :rejected) > 0,
                do: "text-accent-orange-deep",
                else: "text-ink"
            }
          />
        </div>

        <div :if={Scope.manager?(@current_scope)} class="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <.count_card
            label="未承認の日報"
            count={count(@report_counts, :submitted)}
            path={~p"/management/operation_reports?#{%{"status" => "submitted"}}"}
            tone={
              if count(@report_counts, :submitted) > 0, do: "text-accent-orange", else: "text-ink"
            }
          />
          <.count_card
            label="差戻し中の日報"
            count={count(@report_counts, :rejected)}
            path={~p"/management/operation_reports?#{%{"status" => "rejected"}}"}
            tone="text-ink"
          />
          <.count_card
            label="今月の承認済み日報"
            count={count(@report_counts, :approved)}
            path={~p"/management/operation_reports?#{%{"status" => "approved"}}"}
            tone="text-ink"
          />
        </div>

        <section class="rounded-lg border border-hairline bg-canvas-soft p-8 text-center">
          <p class="text-body-md text-ink-muted">
            期限アラート・事故ヒヤリの件数は、各機能の実装後にここへ表示されます。
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :path, :string, required: true
  attr :tone, :string, default: "text-ink"

  defp count_card(assigns) do
    ~H"""
    <.link
      navigate={@path}
      class="block rounded-lg border border-hairline bg-surface p-6 hover:border-primary"
    >
      <p class="text-eyebrow text-ink-muted">{@label}</p>
      <p class={["text-heading-1 mt-2", @tone]}>{@count}</p>
    </.link>
    """
  end

  defp count(counts, status), do: Map.get(counts, status, 0)

  defp role_label(:admin), do: "管理者"
  defp role_label(:manager), do: "運行管理者"
  defp role_label(:member), do: "一般利用者"
end
