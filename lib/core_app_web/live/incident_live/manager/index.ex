defmodule CoreAppWeb.IncidentLive.Manager.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.Incidents
  alias CoreApp.Offices

  alias CoreAppWeb.IncidentLive.Labels

  @filter_keys ~w(q category status office_id shared from to page)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "事故・ヒヤリ")
     |> assign(offices: office_options(socket.assigns.current_scope))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filter_keys)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(page: Incidents.list_incidents(socket.assigns.current_scope, filters))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_patch(socket, to: ~p"/management/incidents?#{clean(params)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          patch={~p"/management/incidents?#{%{"status" => "reported"}}"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          未対応のみ表示
        </.link>
        <.link
          href={~p"/management/exports/incidents?#{@filters}"}
          class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-ink hover:bg-canvas-soft"
        >
          CSV出力
        </.link>
      </:actions>

      <div class="space-y-6">
        <.search_bar params={@filters} placeholder="発生場所・発生状況で検索">
          <:filters>
            <.filter_select
              name="category"
              label="区分"
              value={@filters["category"]}
              options={Labels.category_options()}
            />
            <.filter_select
              name="status"
              label="ステータス"
              value={@filters["status"]}
              options={Labels.status_options()}
            />
            <.filter_select
              :if={Scope.admin?(@current_scope)}
              name="office_id"
              label="拠点"
              value={@filters["office_id"]}
              options={@offices}
            />
            <div class="lg:w-40">
              <label class="text-eyebrow text-ink-muted" for="filter-from">開始日</label>
              <input
                type="date"
                id="filter-from"
                name="from"
                value={@filters["from"]}
                class="text-body-sm mt-1 w-full rounded-xs border border-hairline bg-surface px-2 py-2 text-ink"
              />
            </div>
            <div class="lg:w-40">
              <label class="text-eyebrow text-ink-muted" for="filter-to">終了日</label>
              <input
                type="date"
                id="filter-to"
                name="to"
                value={@filters["to"]}
                class="text-body-sm mt-1 w-full rounded-xs border border-hairline bg-surface px-2 py-2 text-ink"
              />
            </div>
            <.filter_checkbox
              name="shared"
              label="全社共有のみ"
              checked={@filters["shared"] == "true"}
            />
          </:filters>
        </.search_bar>

        <.empty_state
          :if={@page.entries == []}
          message="条件に一致する記録がありません。"
        />

        <div :if={@page.entries != []} class="space-y-4">
          <.data_table
            id="incidents"
            rows={@page.entries}
            row_id={&"incident-#{&1.id}"}
            row_click={&JS.navigate(~p"/management/incidents/#{&1}")}
          >
            <:col :let={incident} label="発生日時">{format_datetime(incident.occurred_at)}</:col>
            <:col :let={incident} label="区分">{Labels.category(incident.category)}</:col>
            <:col :let={incident} label="車両">{incident.vehicle.plate_number}</:col>
            <:col :let={incident} label="場所">{incident.place}</:col>
            <:col :let={incident} :if={Scope.admin?(@current_scope)} label="拠点">
              {incident.office.name}
            </:col>
            <:col :let={incident} label="ステータス">
              <.status_badge status={incident.status} type={:incident} />
            </:col>
          </.data_table>

          <.pagination
            page={@page}
            path={&~p"/management/incidents?#{Map.put(@filters, "page", &1)}"}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp clean(params) do
    params
    |> Map.take(@filter_keys)
    |> Map.delete("page")
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp office_options(scope) do
    if Scope.admin?(scope) do
      Enum.map(Offices.all_offices(), &{&1.name, &1.id})
    else
      []
    end
  end
end
