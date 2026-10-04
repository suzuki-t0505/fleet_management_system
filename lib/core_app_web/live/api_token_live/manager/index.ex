defmodule CoreAppWeb.ApiTokenLive.Manager.Index do
  @moduledoc """
  MCP（外部のAIクライアント）に使うAPIトークンを、自分用に発行・失効する画面です。

  発行直後の1回だけ平文のトークンを表示します（DBにはハッシュしか保存しないため、
  後からは確認できません）。画面を離れる・再読み込みすると表示は消えます。
  """
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts
  alias CoreApp.Accounts.UserToken
  alias CoreApp.Utils.ConvertDatetime

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "APIトークン")
     |> assign(new_token: nil)
     |> assign(validity_days: UserToken.mcp_validity_in_days())
     |> load_tokens()}
  end

  @impl true
  def handle_event("create", _params, socket) do
    case Accounts.create_mcp_token(socket.assigns.current_scope) do
      {:ok, {token, _user_token}} ->
        {:noreply, socket |> assign(new_token: token) |> load_tokens()}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "APIトークンを発行できるのは運行管理者以上です。")}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    case Accounts.revoke_mcp_token(socket.assigns.current_scope, id) do
      {:ok, _user_token} ->
        {:noreply, socket |> put_flash(:info, "APIトークンを失効しました。") |> load_tokens()}

      {:error, :not_found} ->
        {:noreply, socket |> put_flash(:error, "APIトークンが見つかりません。") |> load_tokens()}
    end
  end

  def handle_event("dismiss", _params, socket) do
    {:noreply, assign(socket, new_token: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <button
          id="create-token"
          phx-click="create"
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          トークンを発行
        </button>
      </:actions>

      <div class="space-y-6">
        <.section_card title="APIトークンとは">
          <p class="text-body-sm text-ink-secondary">
            Claude などの MCP クライアントから、あなたの権限・拠点でこのシステムを操作するための鍵です。
            配車表（Excel・スプレッドシート）の取り込みなどに使います。
          </p>
          <ul class="text-body-sm mt-3 list-disc space-y-1 pl-5 text-ink-secondary">
            <li>トークンは<strong>発行直後の1回だけ</strong>表示されます。再表示はできません。</li>
            <li>有効期間は{@validity_days}日です。パスワードと同じく、他人に教えないでください。</li>
            <li>漏れた可能性がある場合は、すぐに失効してください。</li>
          </ul>
        </.section_card>

        <section
          :if={@new_token}
          id="new-token"
          class="rounded-lg border border-accent-orange-deep bg-surface p-6"
        >
          <h2 class="text-title text-accent-orange-deep">発行しました。今のうちにコピーしてください</h2>
          <p class="text-body-sm mt-2 text-ink-secondary">
            この画面を離れると二度と表示できません。
          </p>
          <div class="mt-4 flex items-center gap-2">
            <code
              id="new-token-value"
              class="text-body-sm min-w-0 flex-1 break-all rounded-md border border-hairline bg-canvas-soft px-3 py-2 font-mono text-ink"
            >
              {@new_token}
            </code>
            <button
              id="copy-token"
              type="button"
              phx-click={JS.dispatch("phx:copy", to: "#new-token-value")}
              class="text-button shrink-0 rounded-md border border-hairline bg-surface px-4 py-2 text-ink hover:bg-canvas-soft"
            >
              コピー
            </button>
          </div>
          <p class="text-caption mt-4 text-ink-muted">Claude Code への登録例</p>
          <pre
            id="register-command"
            class="text-caption mt-1 overflow-x-auto rounded-md border border-hairline bg-canvas-soft p-3 font-mono text-ink"
          >claude mcp add --transport http fleet {url(~p"/mcp")} --header "Authorization: Bearer {@new_token}"</pre>
          <button
            phx-click="dismiss"
            class="text-button mt-4 rounded-md border border-hairline bg-surface px-4 py-2 text-ink hover:bg-canvas-soft"
          >
            閉じる
          </button>
        </section>

        <.empty_state
          :if={@tokens == []}
          message="有効なAPIトークンはありません。「トークンを発行」から作成してください。"
        />

        <.data_table :if={@tokens != []} id="tokens" rows={@tokens} row_id={&"token-#{&1.id}"}>
          <:col :let={token} label="発行日時">{format(token.inserted_at)}</:col>
          <:col :let={token} label="有効期限">{format(UserToken.mcp_expires_at(token))}</:col>
          <:col :let={token} label="操作">
            <button
              phx-click="revoke"
              phx-value-id={token.id}
              data-confirm="このAPIトークンを失効します。このトークンを使っているクライアントは接続できなくなります。よろしいですか？"
              class="text-button rounded-md border border-accent-orange-deep px-3 py-1 text-accent-orange-deep hover:bg-canvas-soft"
            >
              失効
            </button>
          </:col>
        </.data_table>
      </div>
    </Layouts.app>
    """
  end

  defp load_tokens(socket) do
    assign(socket, tokens: Accounts.list_mcp_tokens(socket.assigns.current_scope))
  end

  defp format(datetime) do
    datetime |> ConvertDatetime.to_input_value() |> String.replace("T", " ")
  end
end
