defmodule CoreAppWeb.DriverLive.Manager.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.Drivers
  alias CoreApp.Offices

  alias CoreAppWeb.DriverLive.Labels

  @filter_keys ~w(q office_id employment_type page)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "運転者台帳")
     |> assign(offices: office_options(socket.assigns.current_scope))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filter_keys)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(page: Drivers.list_drivers(socket.assigns.current_scope, filters))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      params
      |> Map.take(@filter_keys)
      |> Map.delete("page")
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/management/drivers?#{filters}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          navigate={~p"/management/drivers/new"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          運転者を登録
        </.link>
      </:actions>

      <div class="space-y-6">
        <.search_bar params={@filters} placeholder="氏名・かな・コードで検索">
          <:filters>
            <.filter_select
              :if={Scope.admin?(@current_scope)}
              name="office_id"
              label="拠点"
              value={@filters["office_id"]}
              options={@offices}
            />
            <.filter_select
              name="employment_type"
              label="雇用区分"
              value={@filters["employment_type"]}
              options={Labels.employment_type_options()}
              prompt="退職者以外"
            />
          </:filters>
        </.search_bar>

        <.empty_state
          :if={@page.entries == []}
          message="条件に一致する運転者がいません。"
        >
          <:actions>
            <.link
              navigate={~p"/management/drivers/new"}
              class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
            >
              運転者を登録
            </.link>
          </:actions>
        </.empty_state>

        <div :if={@page.entries != []} class="space-y-4">
          <.data_table
            id="drivers"
            rows={@page.entries}
            row_id={&"driver-#{&1.id}"}
            row_click={&JS.navigate(~p"/management/drivers/#{&1}")}
          >
            <:col :let={driver} label="コード">{driver.code}</:col>
            <:col :let={driver} label="氏名">
              {driver.name}
              <span class="text-caption text-ink-muted">（{driver.name_kana}）</span>
            </:col>
            <:col :let={driver} :if={Scope.admin?(@current_scope)} label="拠点">
              {driver.office.name}
            </:col>
            <:col :let={driver} label="雇用区分">
              {Labels.employment_type(driver.employment_type)}
            </:col>
            <:col :let={driver} label="免許種類">
              {Labels.license_types(driver.license_types)}
            </:col>
            <:col :let={driver} label="免許証有効期限">
              <.deadline_badge date={driver.license_expires_on} />
            </:col>
          </.data_table>

          <.pagination page={@page} path={&page_path(@filters, &1)} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp page_path(filters, page) do
    ~p"/management/drivers?#{Map.put(filters, "page", page)}"
  end

  defp office_options(scope) do
    if Scope.admin?(scope) do
      Enum.map(Offices.all_offices(), &{&1.name, &1.id})
    else
      []
    end
  end
end
