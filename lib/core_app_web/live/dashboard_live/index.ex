defmodule CoreAppWeb.DashboardLive.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "ダッシュボード")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="space-y-6">
        <section class="rounded-lg border border-hairline bg-surface p-6">
          <p class="text-eyebrow text-ink-muted">ようこそ</p>
          <p class="text-heading-2 mt-1">{@current_scope.user.name} さん</p>
          <p class="text-body-sm text-ink-muted mt-2">
            {role_label(@current_scope.role)} ／ {@current_scope.user.office.name}
          </p>
        </section>

        <section class="rounded-lg border border-hairline bg-canvas-soft p-8 text-center">
          <p class="text-body-md text-ink-muted">
            ダッシュボードの内容は準備中です。
          </p>
          <p :if={Scope.manager?(@current_scope)} class="text-body-sm text-ink-faint mt-2">
            期限アラート・未承認日報の件数はこの画面に表示されます。
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp role_label(:admin), do: "管理者"
  defp role_label(:manager), do: "運行管理者"
  defp role_label(:member), do: "一般利用者"
end
