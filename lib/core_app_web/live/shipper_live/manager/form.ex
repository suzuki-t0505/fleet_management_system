defmodule CoreAppWeb.ShipperLive.Manager.Form do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.Offices
  alias CoreApp.Shippers
  alias CoreApp.Shippers.Shipper

  alias CoreAppWeb.ShipperLive.Labels

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(offices: Enum.map(Offices.all_offices(), &{&1.name, &1.id}))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    shipper = %Shipper{office_id: socket.assigns.current_scope.office_id}

    socket
    |> assign(page_title: "荷主を登録")
    |> assign(shipper: shipper)
    |> assign_form(Shippers.change_shipper(shipper))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    shipper = Shippers.get_shipper!(socket.assigns.current_scope, id)

    socket
    |> assign(page_title: "#{shipper.name} を編集")
    |> assign(shipper: shipper)
    |> assign_form(Shippers.change_shipper(shipper))
  end

  @impl true
  def handle_event("validate", %{"shipper" => params}, socket) do
    changeset =
      socket.assigns.shipper
      |> Shippers.change_shipper(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"shipper" => params}, socket) do
    save_shipper(socket, socket.assigns.live_action, params)
  end

  defp save_shipper(socket, :new, params) do
    case Shippers.create_shipper(socket.assigns.current_scope, params) do
      {:ok, shipper} ->
        {:noreply,
         socket
         |> put_flash(:info, "荷主を登録しました。")
         |> push_navigate(to: ~p"/management/shippers/#{shipper}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_shipper(socket, :edit, params) do
    case Shippers.update_shipper(socket.assigns.current_scope, socket.assigns.shipper, params) do
      {:ok, shipper} ->
        {:noreply,
         socket
         |> put_flash(:info, "荷主を更新しました。")
         |> push_navigate(to: ~p"/management/shippers/#{shipper}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.form for={@form} id="shipper-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.section_card title="基本情報">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input field={@form[:name]} type="text" label="荷主名 *" />
            <.input field={@form[:code]} type="text" label="コード" />
            <.input
              :if={Scope.admin?(@current_scope) and @live_action == :new}
              field={@form[:office_id]}
              type="select"
              label="拠点 *"
              prompt="選択してください"
              options={@offices}
            />
            <div :if={!Scope.admin?(@current_scope) or @live_action == :edit}>
              <p class="text-eyebrow text-ink-muted">拠点</p>
              <p class="text-body-sm mt-2 text-ink-secondary">
                {office_name(@shipper, @current_scope)}
              </p>
            </div>
            <.input
              field={@form[:status]}
              type="select"
              label="ステータス *"
              options={Labels.status_options()}
            />
          </div>
        </.section_card>

        <.section_card title="備考">
          <.input field={@form[:note]} type="textarea" label="備考" />
        </.section_card>

        <div class="flex flex-col gap-3 sm:flex-row sm:justify-end">
          <.link
            navigate={cancel_path(@live_action, @shipper)}
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

  defp office_name(%Shipper{office: %{name: name}}, _scope), do: name
  defp office_name(_shipper, scope), do: scope.user.office.name

  defp cancel_path(:new, _shipper), do: ~p"/management/shippers"
  defp cancel_path(:edit, shipper), do: ~p"/management/shippers/#{shipper}"

  defp assign_form(socket, changeset) do
    assign(socket, form: to_form(changeset, as: :shipper))
  end
end
