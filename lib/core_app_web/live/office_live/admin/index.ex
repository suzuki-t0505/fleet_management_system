defmodule CoreAppWeb.OfficeLive.Admin.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Offices

  @filter_keys ~w(q active page)

  @active_options [{"有効のみ", "true"}, {"無効のみ", "false"}, {"すべて", "all"}]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "拠点")
     |> assign(active_options: @active_options)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filter_keys)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(page: Offices.list_offices(socket.assigns.current_scope, filters))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_patch(socket, to: ~p"/management/offices?#{clean(params)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          navigate={~p"/management/offices/new"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          拠点を登録
        </.link>
      </:actions>

      <div class="space-y-6">
        <.search_bar params={@filters} placeholder="拠点コード・拠点名で検索">
          <:filters>
            <.filter_select
              name="active"
              label="状態"
              value={@filters["active"]}
              options={@active_options}
              prompt="有効のみ"
            />
          </:filters>
        </.search_bar>

        <.empty_state
          :if={@page.entries == []}
          message="条件に一致する拠点がありません。"
        >
          <:actions>
            <.link
              navigate={~p"/management/offices/new"}
              class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
            >
              拠点を登録
            </.link>
          </:actions>
        </.empty_state>

        <div :if={@page.entries != []} class="space-y-4">
          <.data_table
            id="offices"
            rows={@page.entries}
            row_id={&"office-#{&1.id}"}
            row_click={&JS.navigate(~p"/management/offices/#{&1}/edit")}
          >
            <:col :let={office} label="拠点コード">{office.code}</:col>
            <:col :let={office} label="拠点名">{office.name}</:col>
            <:col :let={office} label="住所">{office.address || "-"}</:col>
            <:col :let={office} label="電話番号">{office.phone || "-"}</:col>
            <:col :let={office} label="状態">
              <span class={[
                "text-eyebrow inline-block rounded-full px-2 py-1 text-on-primary",
                office.active && "bg-accent-green",
                !office.active && "bg-ink-secondary"
              ]}>
                {active_label(office.active)}
              </span>
            </:col>
          </.data_table>

          <.pagination
            page={@page}
            path={&~p"/management/offices?#{Map.put(@filters, "page", &1)}"}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp active_label(true), do: "有効"
  defp active_label(false), do: "無効"

  defp clean(params) do
    params
    |> Map.take(@filter_keys)
    |> Map.delete("page")
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end
end
