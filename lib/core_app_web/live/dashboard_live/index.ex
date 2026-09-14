defmodule CoreAppWeb.DashboardLive.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.Alerts
  alias CoreApp.Incidents
  alias CoreApp.OperationReports

  alias CoreAppWeb.IncidentLive.Labels
  alias CoreAppWeb.UserLive.Labels, as: UserLabels

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(page_title: "ダッシュボード")
     |> assign(report_counts: OperationReports.count_reports_by_status(scope))
     |> assign(deadline_counts: deadline_counts(scope))
     |> assign(incident_counts: incident_counts(scope))
     |> assign(shared_incidents: Incidents.all_shared_incidents(scope))}
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
            {UserLabels.role(@current_scope.role)} ／ {@current_scope.user.office.name}
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

        <div :if={Scope.manager?(@current_scope)} class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <.count_card
            label="期限超過"
            count={@deadline_counts.overdue}
            path={~p"/management/alerts?#{%{"within" => "overdue"}}"}
            tone={if @deadline_counts.overdue > 0, do: "text-accent-orange-deep", else: "text-ink"}
          />
          <.count_card
            label="期限30日以内"
            count={@deadline_counts.within_30}
            path={~p"/management/alerts?#{%{"within" => "30"}}"}
            tone={if @deadline_counts.within_30 > 0, do: "text-accent-orange", else: "text-ink"}
          />
        </div>

        <div :if={Scope.manager?(@current_scope)} class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <.count_card
            label="未対応の車両不具合報告"
            count={@incident_counts.vehicle_defects}
            path={~p"/management/incidents?#{%{"category" => "single", "status" => "reported"}}"}
            tone={
              if @incident_counts.vehicle_defects > 0,
                do: "text-accent-orange-deep",
                else: "text-ink"
            }
          />
          <.count_card
            label="改善報告が未完了"
            count={@incident_counts.open}
            path={~p"/management/incidents"}
            tone={if @incident_counts.open > 0, do: "text-accent-orange", else: "text-ink"}
          />
        </div>

        <section class="rounded-lg border border-hairline bg-surface p-6">
          <div class="mb-4 flex items-center gap-3">
            <h2 class="text-title">全社共有された事故・ヒヤリ</h2>
            <.link
              navigate={~p"/incidents?#{%{"shared" => "true"}}"}
              class="text-caption ml-auto text-ink-muted hover:text-primary"
            >
              すべて見る
            </.link>
          </div>

          <p :if={@shared_incidents == []} class="text-body-sm text-ink-muted">
            共有された記録はまだありません。
          </p>

          <ul :if={@shared_incidents != []} class="space-y-2">
            <li :for={incident <- @shared_incidents}>
              <.link
                navigate={~p"/incidents/#{incident}"}
                class="block rounded-md border border-hairline px-4 py-3 hover:border-primary"
              >
                <p class="text-caption text-ink-muted">
                  {format_datetime(incident.occurred_at)} ／ {Labels.category(incident.category)}
                </p>
                <p class="text-body-sm mt-1 truncate text-ink-secondary">{incident.place}</p>
              </.link>
            </li>
          </ul>
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

  # 一般利用者は期限の管理対象ではないため、集計そのものを行わない
  defp deadline_counts(scope) do
    if Scope.manager?(scope) do
      Alerts.count_deadlines_by_urgency(scope)
    else
      %{overdue: 0, within_30: 0}
    end
  end

  # 一般利用者には件数を出さないため、集計そのものを行わない
  defp incident_counts(scope) do
    if Scope.manager?(scope) do
      %{
        vehicle_defects: Incidents.count_open_vehicle_defects(scope),
        open: Incidents.count_open_incidents(scope)
      }
    else
      %{vehicle_defects: 0, open: 0}
    end
  end
end
