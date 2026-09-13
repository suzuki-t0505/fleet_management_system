defmodule CoreAppWeb.OperationReportLive.Member.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.OperationReports
  alias CoreApp.Utils.ConvertDatetime

  alias CoreAppWeb.OperationReportLive.Labels

  @filter_keys ~w(status from to page)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "運行日報")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    scope = socket.assigns.current_scope
    filters = Map.take(params, @filter_keys)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(page: OperationReports.list_operation_reports(scope, filters))
     |> assign(rejected: rejected_reports(scope))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      params
      |> Map.take(@filter_keys)
      |> Map.delete("page")
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/operation_reports?#{filters}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          :if={@current_scope.driver_id || Scope.manager?(@current_scope)}
          navigate={~p"/operation_reports/new"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          日報を作成
        </.link>
      </:actions>

      <div class="space-y-6">
        <div
          :if={is_nil(@current_scope.driver_id) && !Scope.manager?(@current_scope)}
          class="rounded-lg border border-accent-orange bg-surface p-4"
        >
          <p class="text-body-sm text-ink-secondary">
            運転者台帳と紐付いていないため、日報を作成できません。運行管理者に紐付けを依頼してください。
          </p>
        </div>

        <div :if={@rejected != []} class="rounded-lg border border-accent-orange-deep bg-surface p-4">
          <p class="text-eyebrow text-accent-orange-deep">差し戻された日報があります</p>
          <ul class="mt-3 space-y-3">
            <li :for={report <- @rejected}>
              <.link
                navigate={~p"/operation_reports/#{report}"}
                class="text-body-sm text-ink hover:text-primary"
              >
                {format_date(report.operation_date)}{report.vehicle.plate_number}
              </.link>
              <p class="text-caption text-ink-muted">理由: {report.rejected_reason}</p>
            </li>
          </ul>
        </div>

        <.search_bar params={@filters} placeholder="">
          <:filters>
            <.filter_select
              name="status"
              label="ステータス"
              value={@filters["status"]}
              options={Labels.status_options()}
            />
            <div class="lg:w-44">
              <label class="text-eyebrow text-ink-muted" for="filter-from">開始日</label>
              <input
                type="date"
                id="filter-from"
                name="from"
                value={@filters["from"] || default_from()}
                class="text-body-sm mt-1 w-full rounded-xs border border-hairline bg-surface px-2 py-2 text-ink"
              />
            </div>
            <div class="lg:w-44">
              <label class="text-eyebrow text-ink-muted" for="filter-to">終了日</label>
              <input
                type="date"
                id="filter-to"
                name="to"
                value={@filters["to"] || default_to()}
                class="text-body-sm mt-1 w-full rounded-xs border border-hairline bg-surface px-2 py-2 text-ink"
              />
            </div>
          </:filters>
        </.search_bar>

        <.empty_state :if={@page.entries == []} message="この期間の日報はありません。" />

        <div :if={@page.entries != []} class="space-y-4">
          <.data_table
            id="operation-reports"
            rows={@page.entries}
            row_id={&"report-#{&1.id}"}
            row_click={&JS.navigate(~p"/operation_reports/#{&1}")}
          >
            <:col :let={report} label="運行日">{format_date(report.operation_date)}</:col>
            <:col :let={report} label="車両">{report.vehicle.plate_number}</:col>
            <:col :let={report} label="走行距離">{report.distance_km} km</:col>
            <:col :let={report} label="出発〜帰着">
              {format_time(report.departed_at)}〜{format_time(report.returned_at)}
            </:col>
            <:col :let={report} label="ステータス">
              <.status_badge status={report.status} type={:operation_report} />
            </:col>
          </.data_table>

          <.pagination page={@page} path={&~p"/operation_reports?#{Map.put(@filters, "page", &1)}"} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp rejected_reports(scope) do
    scope
    |> OperationReports.list_operation_reports(%{
      "status" => "rejected",
      "from" => Date.to_iso8601(Date.add(ConvertDatetime.today(), -90)),
      "to" => Date.to_iso8601(ConvertDatetime.today())
    })
    |> Map.get(:entries)
  end

  defp default_from do
    ConvertDatetime.today() |> Date.beginning_of_month() |> Date.to_iso8601()
  end

  defp default_to do
    ConvertDatetime.today() |> Date.end_of_month() |> Date.to_iso8601()
  end

  defp format_time(datetime) do
    jst = ConvertDatetime.to_jst(datetime)

    "#{String.pad_leading(to_string(jst.hour), 2, "0")}:#{String.pad_leading(to_string(jst.minute), 2, "0")}"
  end
end
