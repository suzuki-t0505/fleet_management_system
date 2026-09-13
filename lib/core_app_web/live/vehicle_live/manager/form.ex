defmodule CoreAppWeb.VehicleLive.Manager.Form do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.Offices
  alias CoreApp.Vehicles
  alias CoreApp.Vehicles.Vehicle

  alias CoreAppWeb.VehicleLive.Labels

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(offices: Enum.map(Offices.all_offices(), &{&1.name, &1.id}))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    vehicle = %Vehicle{office_id: socket.assigns.current_scope.office_id}

    socket
    |> assign(page_title: "車両を登録")
    |> assign(vehicle: vehicle)
    |> assign_form(Vehicles.change_vehicle(vehicle))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    vehicle = Vehicles.get_vehicle!(socket.assigns.current_scope, id)

    socket
    |> assign(page_title: "#{vehicle.plate_number} を編集")
    |> assign(vehicle: vehicle)
    |> assign_form(Vehicles.change_vehicle(vehicle))
  end

  @impl true
  def handle_event("validate", %{"vehicle" => params}, socket) do
    changeset =
      socket.assigns.vehicle
      |> Vehicles.change_vehicle(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"vehicle" => params}, socket) do
    save_vehicle(socket, socket.assigns.live_action, params)
  end

  defp save_vehicle(socket, :new, params) do
    case Vehicles.create_vehicle(socket.assigns.current_scope, params) do
      {:ok, vehicle} ->
        {:noreply,
         socket
         |> put_flash(:info, "車両を登録しました")
         |> push_navigate(to: ~p"/management/vehicles/#{vehicle}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_vehicle(socket, :edit, params) do
    case Vehicles.update_vehicle(socket.assigns.current_scope, socket.assigns.vehicle, params) do
      {:ok, vehicle} ->
        {:noreply,
         socket
         |> put_flash(:info, "車両を更新しました")
         |> push_navigate(to: ~p"/management/vehicles/#{vehicle}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.form for={@form} id="vehicle-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.section_card title="基本情報">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input field={@form[:plate_number]} type="text" label="車両番号 *" />
            <.input field={@form[:vin]} type="text" label="車台番号 *" />
            <.input field={@form[:maker]} type="text" label="メーカー *" />
            <.input field={@form[:model_name]} type="text" label="車名 *" />
            <.input
              field={@form[:vehicle_class]}
              type="select"
              label="車種区分 *"
              prompt="選択してください"
              options={Labels.vehicle_class_options()}
            />
            <.input field={@form[:first_registered_on]} type="date" label="初度登録年月 *" />
            <.input
              :if={Scope.admin?(@current_scope)}
              field={@form[:office_id]}
              type="select"
              label="拠点 *"
              prompt="選択してください"
              options={@offices}
            />
            <div :if={!Scope.admin?(@current_scope)}>
              <p class="text-eyebrow text-ink-muted">拠点</p>
              <p class="text-body-sm mt-2 text-ink-secondary">{@current_scope.user.office.name}</p>
            </div>
            <.input
              field={@form[:status]}
              type="select"
              label="ステータス *"
              options={Labels.status_options()}
            />
          </div>
        </.section_card>

        <.section_card title="期限">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input field={@form[:inspection_expires_on]} type="date" label="車検満了日 *" />
            <.input
              field={@form[:liability_insurance_expires_on]}
              type="date"
              label="自賠責保険満了日 *"
            />
            <.input
              field={@form[:voluntary_insurance_expires_on]}
              type="date"
              label="任意保険満了日"
            />
            <.input field={@form[:next_periodic_3m_on]} type="date" label="次回3ヶ月点検" />
            <.input field={@form[:next_periodic_12m_on]} type="date" label="次回12ヶ月点検" />
          </div>
        </.section_card>

        <.section_card title="諸元">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input field={@form[:capacity_kg]} type="number" label="最大積載量（kg）" />
            <.input field={@form[:gross_weight_kg]} type="number" label="車両総重量（kg）" />
            <.input field={@form[:seating_capacity]} type="number" label="乗車定員（人）" />
            <.input
              field={@form[:fuel_type]}
              type="select"
              label="燃料種別"
              prompt="選択してください"
              options={Labels.fuel_type_options()}
            />
            <.input
              field={@form[:ownership]}
              type="select"
              label="所有区分"
              prompt="選択してください"
              options={Labels.ownership_options()}
            />
            <.input field={@form[:lease_expires_on]} type="date" label="リース満了日" />
          </div>
        </.section_card>

        <.section_card title="備考">
          <.input field={@form[:note]} type="textarea" label="備考" />
        </.section_card>

        <div class="flex flex-col gap-3 sm:flex-row sm:justify-end">
          <.link
            navigate={cancel_path(@live_action, @vehicle)}
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

  defp cancel_path(:new, _vehicle), do: ~p"/management/vehicles"
  defp cancel_path(:edit, vehicle), do: ~p"/management/vehicles/#{vehicle}"

  defp assign_form(socket, changeset) do
    assign(socket, form: to_form(changeset, as: :vehicle))
  end
end
