defmodule CoreAppWeb.UserLive.Admin.Form do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts
  alias CoreApp.Accounts.User
  alias CoreApp.Offices

  alias CoreAppWeb.UserLive.Labels

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(offices: Enum.map(Offices.all_offices(), &{&1.name, &1.id}))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(page_title: "ユーザーを登録")
    |> assign(user: %User{})
    |> assign(self?: false)
    |> assign_form(Accounts.change_user_registration(%User{}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    scope = socket.assigns.current_scope
    user = Accounts.get_user!(scope, id)

    socket
    |> assign(page_title: "#{user.name} を編集")
    |> assign(user: user)
    |> assign(self?: user.id == scope.user.id)
    |> assign_form(Accounts.change_user(user))
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    {:noreply, assign_form(socket, validate(socket, params))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    save_user(socket, socket.assigns.live_action, params)
  end

  def handle_event("send_login_link", _params, socket) do
    user = socket.assigns.user

    Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))

    {:noreply, put_flash(socket, :info, "#{user.email} にログインリンクを送信しました")}
  end

  def handle_event("unlock", _params, socket) do
    case Accounts.unlock_user(socket.assigns.current_scope, socket.assigns.user) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(user: user)
         |> put_flash(:info, "アカウントのロックを解除しました")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "ロックを解除できませんでした")}
    end
  end

  defp validate(socket, params) do
    changeset =
      case socket.assigns.live_action do
        :new -> Accounts.change_user_registration(socket.assigns.user, params)
        :edit -> Accounts.change_user(socket.assigns.user, params)
      end

    Map.put(changeset, :action, :validate)
  end

  defp save_user(socket, :new, params) do
    case Accounts.register_user(socket.assigns.current_scope, params) do
      {:ok, user} ->
        Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))

        {:noreply,
         socket
         |> put_flash(:info, "アカウントを発行し、#{user.email} にログインリンクを送信しました")
         |> push_navigate(to: ~p"/management/users")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_user(socket, :edit, params) do
    case Accounts.update_user(socket.assigns.current_scope, socket.assigns.user, params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "ユーザーを更新しました")
         |> push_navigate(to: ~p"/management/users")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="space-y-6">
        <.form for={@form} id="user-form" phx-change="validate" phx-submit="save" class="space-y-6">
          <.section_card title="基本情報">
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <.input field={@form[:name]} type="text" label="氏名 *" />

              <.input
                :if={@live_action == :new}
                field={@form[:email]}
                type="email"
                label="メールアドレス *"
              />
              <div :if={@live_action == :edit}>
                <p class="text-eyebrow text-ink-muted">メールアドレス</p>
                <p class="text-body-sm mt-2 text-ink-secondary">{@user.email}</p>
                <p class="text-caption text-ink-muted mt-1">
                  メールアドレスの変更は、本人が設定画面から行います。
                </p>
              </div>

              <.input
                field={@form[:office_id]}
                type="select"
                label="所属拠点 *"
                prompt="選択してください"
                options={@offices}
              />
              <.input
                field={@form[:role]}
                type="select"
                label="ロール *"
                options={Labels.role_options()}
                disabled={@self?}
              />
            </div>

            <p :if={@live_action == :new} class="text-caption text-ink-muted mt-4">
              登録すると、初回パスワードを設定するためのログインリンクをメールで送信します。
            </p>
          </.section_card>

          <.section_card :if={@live_action == :edit} title="状態">
            <.input field={@form[:active]} type="checkbox" label="有効にする" disabled={@self?} />
            <p class="text-caption text-ink-muted mt-2">
              無効にするとログインできなくなります。登録済みの日報・記録はそのまま残ります。
            </p>
            <p :if={@self?} class="text-caption text-accent-orange mt-2">
              自分自身のロールと有効フラグは変更できません。管理画面に誰も入れなくなることを防ぐためです。
            </p>
          </.section_card>

          <div class="flex flex-col gap-3 sm:flex-row sm:justify-end">
            <.link
              navigate={~p"/management/users"}
              class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-center text-ink hover:bg-canvas-soft"
            >
              キャンセル
            </.link>
            <button
              type="submit"
              phx-disable-with="保存中..."
              class="text-button rounded-full bg-primary px-6 py-2 text-on-primary hover:bg-primary-active"
            >
              保存
            </button>
          </div>
        </.form>

        <.section_card :if={@live_action == :edit} title="アカウントの操作">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
            <button
              type="button"
              phx-click="send_login_link"
              class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-ink hover:bg-canvas-soft"
            >
              ログインリンクを送信
            </button>
            <button
              :if={User.locked?(@user)}
              type="button"
              phx-click="unlock"
              class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-ink hover:bg-canvas-soft"
            >
              ロックを解除
            </button>
            <p class="text-caption text-ink-muted">
              パスワードを忘れた場合と初回設定は、ログインリンクから行います。
            </p>
          </div>
        </.section_card>
      </div>
    </Layouts.app>
    """
  end

  defp assign_form(socket, changeset) do
    assign(socket, form: to_form(changeset, as: :user))
  end
end
