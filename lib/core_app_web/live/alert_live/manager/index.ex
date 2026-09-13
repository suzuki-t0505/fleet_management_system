defmodule CoreAppWeb.AlertLive.Manager.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.Alerts
  alias CoreApp.Alerts.Deadline
  alias CoreApp.Offices

  @filter_keys ~w(q within alert_type office_id page)

  # 期限種別の表示名は通知メールと共有するため CoreApp.Alerts.Deadline が持つ
  @within_options [{"超過のみ", "overdue"}, {"7日以内", "7"}, {"30日以内", "30"}]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "期限アラート")
     |> assign(offices: office_options(socket.assigns.current_scope))
     |> assign(alert_types: alert_type_options())
     |> assign(within_options: @within_options)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filter_keys)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(page: Alerts.list_deadlines(socket.assigns.current_scope, filters))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_patch(socket, to: ~p"/management/alerts?#{clean(params)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          navigate={~p"/management/maintenances/new"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          点検整備を登録
        </.link>
      </:actions>

      <div class="space-y-6">
        <p class="text-body-sm text-ink-muted">
          期限が近い順に表示します。通知メールは毎朝7時に、対象拠点の運行管理者と管理者へ送られます。
        </p>

        <.search_bar params={@filters} placeholder="車両番号・運転者名で検索">
          <:filters>
            <.filter_select
              name="within"
              label="残日数"
              value={@filters["within"]}
              options={@within_options}
              prompt="60日以内"
            />
            <.filter_select
              name="alert_type"
              label="期限種別"
              value={@filters["alert_type"]}
              options={@alert_types}
            />
            <.filter_select
              :if={Scope.admin?(@current_scope)}
              name="office_id"
              label="拠点"
              value={@filters["office_id"]}
              options={@offices}
            />
          </:filters>
        </.search_bar>

        <.empty_state
          :if={@page.entries == []}
          message="条件に一致する期限がありません。期限切れは発生していません。"
        />

        <div :if={@page.entries != []} class="space-y-4">
          <.data_table
            id="alerts"
            rows={@page.entries}
            row_id={&"alert-#{&1.target_id}-#{&1.alert_type}"}
            row_click={&JS.navigate(target_path(&1))}
          >
            <:col :let={deadline} label="対象">{deadline.target_name}</:col>
            <:col :let={deadline} label="種別">
              {Deadline.target_type_label(deadline.target_type)}
            </:col>
            <:col :let={deadline} label="期限種別">
              {Deadline.alert_type_label(deadline.alert_type)}
            </:col>
            <:col :let={deadline} label="期限日・残日数">
              <.deadline_badge date={deadline.deadline_on} />
            </:col>
            <:col :let={deadline} :if={Scope.admin?(@current_scope)} label="拠点">
              {deadline.office_name}
            </:col>
          </.data_table>

          <.pagination
            page={@page}
            path={&~p"/management/alerts?#{Map.put(@filters, "page", &1)}"}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp target_path(%Deadline{target_type: :vehicle, target_id: id}) do
    ~p"/management/vehicles/#{id}"
  end

  defp target_path(%Deadline{target_type: :driver, target_id: id}) do
    ~p"/management/drivers/#{id}"
  end

  defp clean(params) do
    params
    |> Map.take(@filter_keys)
    |> Map.delete("page")
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp alert_type_options do
    Enum.map(Deadline.alert_types(), &{Deadline.alert_type_label(&1), &1})
  end

  defp office_options(scope) do
    if Scope.admin?(scope) do
      Enum.map(Offices.all_offices(), &{&1.name, &1.id})
    else
      []
    end
  end
end
