defmodule CoreAppWeb.OfficeLive.Admin.Form do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Offices
  alias CoreApp.Offices.Office

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(page_title: "拠点を登録")
    |> assign(office: %Office{})
    |> assign_form(Offices.change_office(%Office{}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    office = Offices.get_office!(id)

    socket
    |> assign(page_title: "#{office.name} を編集")
    |> assign(office: office)
    |> assign_form(Offices.change_office(office))
  end

  @impl true
  def handle_event("validate", %{"office" => params}, socket) do
    changeset =
      socket.assigns.office
      |> Offices.change_office(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"office" => params}, socket) do
    save_office(socket, socket.assigns.live_action, params)
  end

  defp save_office(socket, :new, params) do
    case Offices.create_office(params) do
      {:ok, _office} ->
        {:noreply,
         socket
         |> put_flash(:info, "拠点を登録しました")
         |> push_navigate(to: ~p"/management/offices")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_office(socket, :edit, params) do
    case Offices.update_office(socket.assigns.office, params) do
      {:ok, _office} ->
        {:noreply,
         socket
         |> put_flash(:info, "拠点を更新しました")
         |> push_navigate(to: ~p"/management/offices")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.form for={@form} id="office-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.section_card title="拠点情報">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input field={@form[:code]} type="text" label="拠点コード *" />
            <.input field={@form[:name]} type="text" label="拠点名 *" />
            <.input
              field={@form[:postal_code]}
              type="text"
              label="郵便番号"
              placeholder="100-0001"
            />
            <.input field={@form[:phone]} type="text" label="電話番号" />
            <div class="sm:col-span-2">
              <.input field={@form[:address]} type="text" label="住所" />
            </div>
          </div>
        </.section_card>

        <.section_card title="状態">
          <.input field={@form[:active]} type="checkbox" label="有効にする" />
          <p class="text-caption text-ink-muted mt-2">
            拠点は削除できません。使わなくなった拠点は無効にしてください。
            無効にすると、車両・運転者・ユーザーの拠点の選択肢に表示されなくなります。
          </p>
        </.section_card>

        <div class="flex flex-col gap-3 sm:flex-row sm:justify-end">
          <.link
            navigate={~p"/management/offices"}
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
    </Layouts.app>
    """
  end

  defp assign_form(socket, changeset) do
    assign(socket, form: to_form(changeset, as: :office))
  end
end
