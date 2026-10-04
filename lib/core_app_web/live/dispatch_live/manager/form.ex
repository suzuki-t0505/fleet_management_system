defmodule CoreAppWeb.DispatchLive.Manager.Form do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Dispatches
  alias CoreApp.Dispatches.Dispatch
  alias CoreApp.Drivers
  alias CoreApp.Shippers
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Vehicles

  alias CoreAppWeb.DispatchLive.Labels

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    scope = socket.assigns.current_scope
    dispatch = %Dispatch{deliveries: []}

    socket
    |> assign(page_title: "配車を登録")
    |> assign(dispatch: dispatch)
    |> assign_options(nil)
    |> assign_form(Dispatches.change_dispatch(dispatch, scope))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    scope = socket.assigns.current_scope
    dispatch = Dispatches.get_dispatch!(scope, id)

    socket
    |> assign(page_title: "配車を編集")
    |> assign(dispatch: dispatch)
    |> assign_options(dispatch.shipper_id)
    |> assign_form(Dispatches.change_dispatch(dispatch, scope))
  end

  @impl true
  def handle_event("validate", %{"dispatch" => params}, socket) do
    changeset =
      socket.assigns.dispatch
      |> Dispatches.change_dispatch(socket.assigns.current_scope, params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"dispatch" => params}, socket) do
    save_dispatch(socket, socket.assigns.live_action, params)
  end

  defp save_dispatch(socket, :new, params) do
    case Dispatches.create_dispatch(socket.assigns.current_scope, params) do
      {:ok, dispatch} ->
        {:noreply,
         socket
         |> put_flash(:info, "配車を登録しました。")
         |> push_navigate(to: ~p"/management/dispatches/#{dispatch}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_dispatch(socket, :edit, params) do
    scope = socket.assigns.current_scope

    case Dispatches.update_dispatch(scope, socket.assigns.dispatch, params) do
      {:ok, dispatch} ->
        {:noreply,
         socket
         |> put_flash(:info, "配車を更新しました。")
         |> push_navigate(to: ~p"/management/dispatches/#{dispatch}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.form for={@form} id="dispatch-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <div :if={@warnings != []} class="rounded-lg border border-accent-orange bg-surface p-4">
          <p class="text-eyebrow text-accent-orange">確認してください</p>
          <ul class="mt-2 space-y-1">
            <li :for={warning <- @warnings} class="text-body-sm text-ink-secondary">{warning}</li>
          </ul>
          <p class="text-caption text-ink-muted mt-2">
            内容に問題がなければ、そのまま保存できます。
          </p>
        </div>

        <.section_card title="配送">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div class="sm:col-span-2">
              <.input field={@form[:title]} type="text" label="配送タイトル *" />
            </div>
            <.input
              field={@form[:started_at]}
              type="datetime-local"
              label="配送開始日時 *"
              value={ConvertDatetime.to_input_value(@form[:started_at].value)}
            />
            <.input
              field={@form[:ended_at]}
              type="datetime-local"
              label="配送終了日時 *"
              value={ConvertDatetime.to_input_value(@form[:ended_at].value)}
            />
            <.input
              field={@form[:shipper_id]}
              type="select"
              label="荷主 *"
              prompt="選択してください"
              options={@shippers}
            />
            <.input
              field={@form[:vehicle_id]}
              type="select"
              label="車両 *"
              prompt="選択してください"
              options={@vehicles}
            />
            <.input
              field={@form[:driver_id]}
              type="select"
              label="ドライバー *"
              prompt="選択してください"
              options={@drivers}
            />
            <div class="sm:col-span-2">
              <.input field={@form[:description]} type="textarea" label="配送説明" />
            </div>
          </div>
        </.section_card>

        <.section_card title="料金">
          <fieldset class="space-y-2">
            <legend class="text-eyebrow text-ink-muted">料金方式 *</legend>
            <div class="flex flex-wrap gap-4">
              <label
                :for={{label, value} <- Labels.pricing_type_options()}
                class="text-body-sm inline-flex cursor-pointer items-center gap-2 text-ink-secondary"
              >
                <input
                  type="radio"
                  name={@form[:pricing_type].name}
                  value={value}
                  checked={to_string(@form[:pricing_type].value) == to_string(value)}
                />
                {label}
              </label>
            </div>
          </fieldset>

          <div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input
              :if={pricing_type(@form) == "course_total"}
              field={@form[:course_fare_yen]}
              type="number"
              label="コース料金（円）*"
            />
            <.input field={@form[:toll_yen]} type="number" label="高速料金（円）" />
          </div>
        </.section_card>

        <.section_card title={destination_title(@form)}>
          <:actions>
            <label class="text-button cursor-pointer rounded-md border border-hairline px-3 py-1 text-ink hover:bg-canvas-soft">
              配送先を追加
              <input
                type="checkbox"
                name="dispatch[deliveries_sort][]"
                class="hidden"
                value="new"
                phx-click={JS.dispatch("change", to: "#dispatch-form")}
              />
            </label>
          </:actions>

          <p :if={@form[:deliveries].errors != []} class="text-body-sm mb-3 text-accent-orange-deep">
            配送先{elem(hd(@form[:deliveries].errors), 0)}
          </p>

          <p :if={@form[:deliveries].value in [[], nil]} class="text-body-sm text-ink-muted">
            配送先がまだありません。「配送先を追加」から入力してください。
          </p>

          <div class="space-y-4">
            <.inputs_for :let={delivery} field={@form[:deliveries]}>
              <div class="rounded-md border border-hairline p-4">
                <input type="hidden" name="dispatch[deliveries_sort][]" value={delivery.index} />
                <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                  <.input field={delivery[:destination]} type="text" label="配送先 *" />
                  <.input
                    :if={pricing_type(@form) == "per_delivery"}
                    field={delivery[:fare_yen]}
                    type="number"
                    label="配送料金（円）*"
                  />
                  <.input
                    field={delivery[:loading_at]}
                    type="datetime-local"
                    label="荷積み日時"
                    value={ConvertDatetime.to_input_value(delivery[:loading_at].value)}
                  />
                  <.input
                    field={delivery[:unloading_at]}
                    type="datetime-local"
                    label="荷降ろし日時"
                    value={ConvertDatetime.to_input_value(delivery[:unloading_at].value)}
                  />
                </div>
                <label class="text-caption mt-3 inline-flex cursor-pointer items-center gap-1 text-accent-orange-deep">
                  <input
                    type="checkbox"
                    name="dispatch[deliveries_drop][]"
                    value={delivery.index}
                    class="hidden"
                    phx-click={JS.dispatch("change", to: "#dispatch-form")}
                  />
                  <.icon name="hero-trash" class="size-4" /> この配送先を削除
                </label>
              </div>
            </.inputs_for>
          </div>

          <input type="hidden" name="dispatch[deliveries_drop][]" />
        </.section_card>

        <div class="rounded-lg border border-hairline bg-surface p-4">
          <p class="text-eyebrow text-ink-muted">受取金額の合計（プレビュー）</p>
          <p id="dispatch-total-preview" class="text-title mt-1 text-ink">
            {Labels.yen(@total_amount_yen)}
          </p>
        </div>

        <div class="flex flex-col gap-3 sm:flex-row sm:justify-end">
          <.link
            navigate={cancel_path(@live_action, @dispatch)}
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

  defp pricing_type(form), do: to_string(form[:pricing_type].value)

  defp destination_title(form) do
    if pricing_type(form) == "per_delivery", do: "配送明細（配送先と配送料金）", else: "配送先"
  end

  defp cancel_path(:new, _dispatch), do: ~p"/management/dispatches"
  defp cancel_path(:edit, dispatch), do: ~p"/management/dispatches/#{dispatch}"

  defp assign_options(socket, current_shipper_id) do
    scope = socket.assigns.current_scope

    socket
    |> assign(
      shippers:
        Enum.map(Shippers.all_selectable_shippers(scope, current_shipper_id), &{&1.name, &1.id})
    )
    |> assign(
      vehicles:
        Enum.map(
          Vehicles.all_selectable_vehicles(scope),
          &{"#{&1.plate_number}（#{&1.model_name}）", &1.id}
        )
    )
    |> assign(drivers: Enum.map(Drivers.all_selectable_drivers(scope), &{&1.name, &1.id}))
  end

  defp assign_form(socket, changeset) do
    socket
    |> assign(form: to_form(changeset, as: :dispatch))
    |> assign(warnings: Dispatches.warnings(socket.assigns.current_scope, changeset))
    |> assign(total_amount_yen: Dispatches.total_amount_yen(changeset))
  end
end
