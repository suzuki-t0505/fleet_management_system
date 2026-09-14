defmodule CoreAppWeb.IncidentLive.Member.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Incidents

  alias CoreAppWeb.IncidentLive.Labels

  @filter_keys ~w(category status shared page)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "事故・ヒヤリ")}
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
    {:noreply, push_patch(socket, to: ~p"/incidents?#{clean(params)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          navigate={~p"/incidents/new"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          報告する
        </.link>
      </:actions>

      <div class="space-y-6">
        <p class="text-body-sm text-ink-muted">
          自分が報告した記録・自分が運転者の記録と、全社で共有された記録を表示します。
        </p>

        <.search_bar params={@filters} placeholder="">
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
        >
          <:actions>
            <.link
              navigate={~p"/incidents/new"}
              class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
            >
              報告する
            </.link>
          </:actions>
        </.empty_state>

        <div :if={@page.entries != []} class="space-y-4">
          <.data_table
            id="incidents"
            rows={@page.entries}
            row_id={&"incident-#{&1.id}"}
            row_click={&JS.navigate(~p"/incidents/#{&1}")}
          >
            <:col :let={incident} label="発生日時">{format_datetime(incident.occurred_at)}</:col>
            <:col :let={incident} label="区分">{Labels.category(incident.category)}</:col>
            <:col :let={incident} label="場所">{incident.place}</:col>
            <:col :let={incident} label="車両">{incident.vehicle.plate_number}</:col>
            <:col :let={incident} label="ステータス">
              <.status_badge status={incident.status} type={:incident} />
            </:col>
            <:col :let={incident} label="全社共有">{shared_label(incident)}</:col>
          </.data_table>

          <.pagination page={@page} path={&~p"/incidents?#{Map.put(@filters, "page", &1)}"} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp shared_label(%{shared_company_wide: true}), do: "共有"
  defp shared_label(_incident), do: "-"

  defp clean(params) do
    params
    |> Map.take(@filter_keys)
    |> Map.delete("page")
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end
end
