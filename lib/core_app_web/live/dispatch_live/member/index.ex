defmodule CoreAppWeb.DispatchLive.Member.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Dispatches

  @filter_keys ~w(q from to page)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "配車")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filter_keys)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(page: Dispatches.list_dispatches(socket.assigns.current_scope, filters))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      params
      |> Map.take(@filter_keys)
      |> Map.delete("page")
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/dispatches?#{filters}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          navigate={~p"/dispatches/board"}
          class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-ink hover:bg-canvas-soft"
        >
          配車表
        </.link>
      </:actions>

      <div class="space-y-6">
        <.search_bar params={@filters} placeholder="タイトル・荷主・配送先で検索">
          <:filters>
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
          </:filters>
        </.search_bar>

        <.empty_state
          :if={@page.entries == []}
          message="あなたに割り当てられた配車はありません。"
        />

        <div :if={@page.entries != []} class="space-y-4">
          <.data_table
            id="dispatches"
            rows={@page.entries}
            row_id={&"dispatch-#{&1.id}"}
            row_click={&JS.navigate(~p"/dispatches/#{&1}")}
          >
            <:col :let={dispatch} label="配送日時">
              {format_datetime(dispatch.started_at)}
              <span class="text-caption text-ink-muted">〜 {format_datetime(dispatch.ended_at)}</span>
            </:col>
            <:col :let={dispatch} label="タイトル">{dispatch.title}</:col>
            <:col :let={dispatch} label="荷主">{dispatch.shipper.name}</:col>
            <:col :let={dispatch} label="車両">{dispatch.vehicle.plate_number}</:col>
          </.data_table>

          <.pagination page={@page} path={&page_path(@filters, &1)} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp page_path(filters, page) do
    ~p"/dispatches?#{Map.put(filters, "page", page)}"
  end
end
