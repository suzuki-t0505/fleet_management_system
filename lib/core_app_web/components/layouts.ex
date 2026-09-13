defmodule CoreAppWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CoreAppWeb, :html

  alias CoreApp.Accounts.Scope

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :page_title, :string, default: nil, doc: "ヘッダーに表示するページタイトル"

  slot :actions, doc: "ヘッダー右側に置くアクション"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-canvas-soft font-sans text-ink">
      <div class="lg:flex">
        <%!-- サイドバーの開閉はCSSのみで行う（LiveViewの接続前でも動作させるため） --%>
        <input id="nav-toggle" type="checkbox" class="peer sr-only" aria-hidden="true" />

        <.sidebar current_scope={@current_scope} />

        <div class="min-w-0 flex-1">
          <header class="flex items-center gap-3 border-b border-hairline bg-canvas px-4 py-3">
            <label
              for="nav-toggle"
              class="cursor-pointer rounded-md p-1 text-ink-muted hover:bg-canvas-soft lg:hidden"
              aria-label="メニューを開く"
            >
              <.icon name="hero-bars-3" class="size-6" />
            </label>
            <h1 class="text-title truncate">{@page_title}</h1>
            <div class="ml-auto flex items-center gap-2">{render_slot(@actions)}</div>
          </header>

          <main class="px-4 py-6">
            <div class="mx-auto max-w-[1280px]">
              {render_slot(@inner_block)}
            </div>
          </main>
        </div>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :current_scope, :map, default: nil

  defp sidebar(assigns) do
    ~H"""
    <nav
      id="mobile-nav"
      class="hidden w-full shrink-0 border-b border-hairline bg-canvas px-4 py-4 peer-checked:block lg:block lg:h-screen lg:w-60 lg:border-r lg:border-b-0"
    >
      <div class="flex h-full flex-col">
        <div class="pb-6">
          <p class="text-title">車両管理</p>
          <p class="text-eyebrow text-ink-faint">Fleet Management</p>
        </div>

        <ul class="flex-1 space-y-1">
          <li :for={item <- nav_items(@current_scope)}>
            <.nav_item item={item} />
          </li>
        </ul>

        <div :if={@current_scope && @current_scope.user} class="border-t border-hairline pt-3">
          <p class="text-body-sm truncate">{@current_scope.user.name}</p>
          <p class="text-caption text-ink-muted truncate">
            {office_name(@current_scope)} ／ {role_label(@current_scope.role)}
          </p>
          <div class="mt-2 flex gap-2">
            <.link
              navigate={~p"/users/settings"}
              class="text-caption text-ink-muted hover:text-primary"
            >
              設定
            </.link>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="text-caption text-ink-muted hover:text-primary"
            >
              ログアウト
            </.link>
          </div>
        </div>
      </div>
    </nav>
    """
  end

  attr :item, :map, required: true

  defp nav_item(%{item: %{path: nil}} = assigns) do
    ~H"""
    <span
      class="text-body-sm text-ink-faint flex cursor-not-allowed items-center gap-2 rounded-sm px-3 py-2"
      title="準備中"
    >
      <.icon name={@item.icon} class="size-4 shrink-0" />
      {@item.label}
    </span>
    """
  end

  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@item.path}
      class="text-body-sm text-ink-secondary flex items-center gap-2 rounded-sm px-3 py-2 hover:bg-canvas-soft"
    >
      <.icon name={@item.icon} class="size-4 shrink-0" />
      {@item.label}
    </.link>
    """
  end

  # path が nil の項目は未実装。機能の実装に合わせてパスを設定していく。
  defp nav_items(scope) do
    base = [
      %{label: "ダッシュボード", icon: "hero-home", path: "/"},
      %{label: "運行日報", icon: "hero-document-text", path: nil},
      %{label: "事故・ヒヤリ", icon: "hero-exclamation-triangle", path: nil},
      %{label: "車両", icon: "hero-truck", path: vehicles_path(scope)}
    ]

    manager = [
      %{label: "運転者", icon: "hero-identification", path: "/management/drivers"},
      %{label: "点検整備・期限", icon: "hero-wrench-screwdriver", path: nil},
      %{label: "集計", icon: "hero-chart-bar", path: nil}
    ]

    admin = [
      %{label: "ユーザー", icon: "hero-users", path: nil},
      %{label: "拠点", icon: "hero-building-office", path: nil},
      %{label: "監査ログ", icon: "hero-clipboard-document-list", path: nil}
    ]

    cond do
      Scope.admin?(scope) -> base ++ manager ++ admin
      Scope.manager?(scope) -> base ++ manager
      true -> base
    end
  end

  # 運行管理者・管理者は台帳（編集可）、一般利用者は参照専用の画面へ遷移する
  defp vehicles_path(scope) do
    if Scope.manager?(scope), do: "/management/vehicles", else: "/vehicles"
  end

  defp office_name(%{user: %{office: %{name: name}}}), do: name
  defp office_name(_scope), do: "-"

  defp role_label(:admin), do: "管理者"
  defp role_label(:manager), do: "運行管理者"
  defp role_label(:member), do: "一般利用者"
  defp role_label(_role), do: "-"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
