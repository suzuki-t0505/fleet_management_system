defmodule CoreAppWeb.UserLive.Admin.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts
  alias CoreApp.Accounts.User
  alias CoreApp.Offices

  alias CoreAppWeb.UserLive.Labels

  @filter_keys ~w(q office_id role active page)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "ユーザー")
     |> assign(offices: Enum.map(Offices.all_offices(), &{&1.name, &1.id}))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filter_keys)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(page: Accounts.list_users(socket.assigns.current_scope, filters))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_patch(socket, to: ~p"/management/users?#{clean(params)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          navigate={~p"/management/users/new"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          ユーザーを登録
        </.link>
      </:actions>

      <div class="space-y-6">
        <.search_bar params={@filters} placeholder="氏名・メールアドレスで検索">
          <:filters>
            <.filter_select
              name="office_id"
              label="拠点"
              value={@filters["office_id"]}
              options={@offices}
            />
            <.filter_select
              name="role"
              label="ロール"
              value={@filters["role"]}
              options={Labels.role_options()}
            />
            <.filter_select
              name="active"
              label="状態"
              value={@filters["active"]}
              options={Labels.active_options()}
              prompt="有効のみ"
            />
          </:filters>
        </.search_bar>

        <.empty_state
          :if={@page.entries == []}
          message="条件に一致するユーザーがいません。"
        >
          <:actions>
            <.link
              navigate={~p"/management/users/new"}
              class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
            >
              ユーザーを登録
            </.link>
          </:actions>
        </.empty_state>

        <div :if={@page.entries != []} class="space-y-4">
          <.data_table
            id="users"
            rows={@page.entries}
            row_id={&"user-#{&1.id}"}
            row_click={&JS.navigate(~p"/management/users/#{&1}/edit")}
          >
            <:col :let={user} label="氏名">{user.name}</:col>
            <:col :let={user} label="メールアドレス">{user.email}</:col>
            <:col :let={user} label="拠点">{user.office.name}</:col>
            <:col :let={user} label="ロール">{Labels.role(user.role)}</:col>
            <:col :let={user} label="運転者">{driver_name(user)}</:col>
            <:col :let={user} label="状態">
              <.status_badge status={User.status(user)} type={:user} />
            </:col>
          </.data_table>

          <.pagination page={@page} path={&~p"/management/users?#{Map.put(@filters, "page", &1)}"} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp driver_name(%User{driver: %{name: name}}), do: name
  defp driver_name(_user), do: "-"

  defp clean(params) do
    params
    |> Map.take(@filter_keys)
    |> Map.delete("page")
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end
end
