defmodule CoreAppWeb.AuditLogLive.Admin.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.AuditLogs

  alias CoreAppWeb.AuditLogLive.Labels

  @filter_keys ~w(q resource_type action user_id page)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "監査ログ")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filter_keys)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(page: AuditLogs.list_audit_logs(socket.assigns.current_scope, filters))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_patch(socket, to: ~p"/management/audit_logs?#{clean(params)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="space-y-6">
        <p class="text-body-sm text-ink-muted">
          台帳の変更・日報の承認・権限の変更を記録しています。追記専用のため、編集・削除はできません。
        </p>

        <.search_bar
          params={@filters}
          placeholder="操作者の氏名・メールアドレスで検索"
        >
          <:filters>
            <.filter_select
              name="resource_type"
              label="対象"
              value={@filters["resource_type"]}
              options={Labels.resource_type_options()}
            />
            <.filter_select
              name="action"
              label="操作"
              value={@filters["action"]}
              options={Labels.action_options()}
            />
          </:filters>
        </.search_bar>

        <.empty_state
          :if={@page.entries == []}
          message="条件に一致する監査ログがありません。"
        />

        <div :if={@page.entries != []} class="space-y-4">
          <.data_table id="audit-logs" rows={@page.entries} row_id={&"audit-log-#{&1.id}"}>
            <:col :let={log} label="操作日時">{format_datetime(log.inserted_at)}</:col>
            <:col :let={log} label="操作者">{log.user.name}</:col>
            <:col :let={log} label="対象">{Labels.resource_type(log.resource_type)}</:col>
            <:col :let={log} label="操作">{Labels.action(log.action)}</:col>
            <:col :let={log} label="対象ID" class="font-mono text-caption">{log.resource_id}</:col>
            <:col :let={log} label="変更内容">
              <ul :if={changes(log) != []} class="space-y-1">
                <li :for={change <- changes(log)} class="text-caption text-ink-secondary">
                  {change}
                </li>
              </ul>
              <span :if={changes(log) == []} class="text-caption text-ink-faint">-</span>
            </:col>
          </.data_table>

          <.pagination
            page={@page}
            path={&~p"/management/audit_logs?#{Map.put(@filters, "page", &1)}"}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  # 変更差分は key と値の組で保存されている。表示用の文字列に整形する。
  defp changes(%{changes: changes}) when is_map(changes) do
    changes
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> "#{key}: #{format_value(value)}" end)
  end

  defp changes(_log), do: []

  defp format_value(value) when is_binary(value), do: value
  defp format_value(true), do: "有効"
  defp format_value(false), do: "無効"
  defp format_value(nil), do: "（なし）"
  defp format_value(value) when is_list(value), do: Enum.join(value, "、")
  defp format_value(value), do: to_string(value)

  defp clean(params) do
    params
    |> Map.take(@filter_keys)
    |> Map.delete("page")
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end
end
