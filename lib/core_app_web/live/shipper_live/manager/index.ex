defmodule CoreAppWeb.ShipperLive.Manager.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.Offices
  alias CoreApp.Shippers

  alias CoreAppWeb.ShipperLive.Labels

  @filter_keys ~w(q office_id status page)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "荷主")
     |> assign(offices: office_options(socket.assigns.current_scope))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filter_keys)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(page: Shippers.list_shippers(socket.assigns.current_scope, filters))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      params
      |> Map.take(@filter_keys)
      |> Map.delete("page")
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/management/shippers?#{filters}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          navigate={~p"/management/shippers/new"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          荷主を登録
        </.link>
      </:actions>

      <div class="space-y-6">
        <.search_bar params={@filters} placeholder="荷主名・コードで検索">
          <:filters>
            <.filter_select
              :if={Scope.admin?(@current_scope)}
              name="office_id"
              label="拠点"
              value={@filters["office_id"]}
              options={@offices}
            />
            <.filter_select
              name="status"
              label="ステータス"
              value={@filters["status"]}
              options={Labels.status_options()}
              prompt="有効のみ"
            />
          </:filters>
        </.search_bar>

        <.empty_state
          :if={@page.entries == []}
          message="条件に一致する荷主がありません。"
        >
          <:actions>
            <.link
              navigate={~p"/management/shippers/new"}
              class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
            >
              荷主を登録
            </.link>
          </:actions>
        </.empty_state>

        <div :if={@page.entries != []} class="space-y-4">
          <.data_table
            id="shippers"
            rows={@page.entries}
            row_id={&"shipper-#{&1.id}"}
            row_click={&JS.navigate(~p"/management/shippers/#{&1}")}
          >
            <:col :let={shipper} label="荷主名">{shipper.name}</:col>
            <:col :let={shipper} label="コード">{shipper.code || "-"}</:col>
            <:col :let={shipper} :if={Scope.admin?(@current_scope)} label="拠点">
              {shipper.office.name}
            </:col>
            <:col :let={shipper} label="ステータス">
              <.status_badge status={shipper.status} type={:shipper} />
            </:col>
          </.data_table>

          <.pagination page={@page} path={&page_path(@filters, &1)} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp page_path(filters, page) do
    ~p"/management/shippers?#{Map.put(filters, "page", page)}"
  end

  defp office_options(scope) do
    if Scope.admin?(scope) do
      Enum.map(Offices.all_offices(), &{&1.name, &1.id})
    else
      []
    end
  end
end
