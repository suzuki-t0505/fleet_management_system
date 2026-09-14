defmodule CoreAppWeb.MaintenanceLive.Manager.Form do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Maintenances
  alias CoreApp.Maintenances.Maintenance
  alias CoreApp.Vehicles

  alias CoreAppWeb.MaintenanceLive.Labels

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(vehicles: vehicle_options(socket.assigns.current_scope))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, params) do
    scope = socket.assigns.current_scope
    maintenance = %Maintenance{vehicle_id: params["vehicle_id"]}

    socket
    |> assign(page_title: "点検整備記録を登録")
    |> assign(maintenance: maintenance)
    |> assign_form(Maintenances.change_maintenance(maintenance, scope, %{}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    scope = socket.assigns.current_scope
    maintenance = Maintenances.get_maintenance!(scope, id)

    socket
    |> assign(page_title: "点検整備記録を編集")
    |> assign(maintenance: maintenance)
    |> assign_form(Maintenances.change_maintenance(maintenance, scope, %{}))
  end

  @impl true
  def handle_event("validate", %{"maintenance" => params}, socket) do
    changeset =
      socket.assigns.maintenance
      |> Maintenances.change_maintenance(socket.assigns.current_scope, params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"maintenance" => params}, socket) do
    save_maintenance(socket, socket.assigns.live_action, params)
  end

  defp save_maintenance(socket, :new, params) do
    case Maintenances.create_maintenance(socket.assigns.current_scope, params) do
      {:ok, maintenance} ->
        {:noreply,
         socket
         |> put_flash(:info, "点検整備記録を登録しました")
         |> push_navigate(to: ~p"/management/maintenances/#{maintenance}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_maintenance(socket, :edit, params) do
    scope = socket.assigns.current_scope

    case Maintenances.update_maintenance(scope, socket.assigns.maintenance, params) do
      {:ok, maintenance} ->
        {:noreply,
         socket
         |> put_flash(:info, "点検整備記録を更新しました")
         |> push_navigate(to: ~p"/management/maintenances/#{maintenance}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.form
        for={@form}
        id="maintenance-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <div :if={@warnings != []} class="rounded-lg border border-accent-orange bg-surface p-4">
          <p class="text-eyebrow text-accent-orange">確認してください</p>
          <ul class="mt-2 space-y-1">
            <li :for={warning <- @warnings} class="text-body-sm text-ink-secondary">{warning}</li>
          </ul>
          <p class="text-caption text-ink-muted mt-2">
            内容に問題がなければ、そのまま保存できます。
          </p>
        </div>

        <.section_card title="実施内容">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input
              field={@form[:vehicle_id]}
              type="select"
              label="車両 *"
              prompt="選択してください"
              options={@vehicles}
            />
            <.input field={@form[:performed_on]} type="date" label="実施日 *" />
            <.input
              field={@form[:category]}
              type="select"
              label="区分 *"
              prompt="選択してください"
              options={Labels.category_options()}
            />
            <.input field={@form[:odometer]} type="number" label="オドメーター（km） *" />
            <.input field={@form[:vendor]} type="text" label="実施業者 *" />
            <.input field={@form[:cost_yen]} type="number" label="費用（円・税込）" />
          </div>
        </.section_card>

        <.section_card title="次回予定">
          <.input
            field={@form[:next_scheduled_on]}
            type="date"
            label={Labels.next_scheduled_label(@category)}
          />
          <p class="text-caption text-ink-muted mt-2">{Labels.next_scheduled_hint(@category)}</p>
          <p :if={@live_action == :edit} class="text-caption text-ink-muted mt-1">
            区分を変更した場合、変更前の区分で更新した車両の期限は戻りません。車両台帳から直してください。
          </p>
        </.section_card>

        <.section_card title="作業内容">
          <.input field={@form[:description]} type="textarea" label="作業内容" />
        </.section_card>

        <div class="flex flex-col gap-3 sm:flex-row sm:justify-end">
          <.link
            navigate={cancel_path(@live_action, @maintenance)}
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

  defp cancel_path(:new, _maintenance), do: ~p"/management/maintenances"
  defp cancel_path(:edit, maintenance), do: ~p"/management/maintenances/#{maintenance}"

  defp assign_form(socket, changeset) do
    socket
    |> assign(form: to_form(changeset, as: :maintenance))
    |> assign(category: Ecto.Changeset.get_field(changeset, :category))
    |> assign(warnings: Maintenances.warnings(socket.assigns.current_scope, changeset))
  end

  defp vehicle_options(scope) do
    scope
    |> Vehicles.all_selectable_vehicles()
    |> Enum.map(&{"#{&1.plate_number}（#{&1.model_name}）", &1.id})
  end
end
