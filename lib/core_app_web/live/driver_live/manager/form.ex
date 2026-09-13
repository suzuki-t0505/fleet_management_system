defmodule CoreAppWeb.DriverLive.Manager.Form do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.Drivers
  alias CoreApp.Drivers.Driver
  alias CoreApp.Offices
  alias CoreApp.Utils.ConvertDatetime

  alias CoreAppWeb.DriverLive.Labels

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(offices: Enum.map(Offices.all_offices(), &{&1.name, &1.id}))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    driver = %Driver{office_id: socket.assigns.current_scope.office_id}

    socket
    |> assign(page_title: "運転者を登録")
    |> assign(driver: driver)
    |> assign(users: Drivers.all_linkable_users(socket.assigns.current_scope))
    |> assign_form(Drivers.change_driver(driver))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    driver = Drivers.get_driver!(socket.assigns.current_scope, id)

    socket
    |> assign(page_title: "#{driver.name} を編集")
    |> assign(driver: driver)
    |> assign(users: Drivers.all_linkable_users(socket.assigns.current_scope, driver))
    |> assign_form(Drivers.change_driver(driver))
  end

  @impl true
  def handle_event("validate", %{"driver" => params}, socket) do
    changeset =
      socket.assigns.driver
      |> Drivers.change_driver(normalize(params))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"driver" => params}, socket) do
    save_driver(socket, socket.assigns.live_action, normalize(params))
  end

  defp save_driver(socket, :new, params) do
    case Drivers.create_driver(socket.assigns.current_scope, params) do
      {:ok, driver} ->
        {:noreply,
         socket
         |> put_flash(:info, "運転者を登録しました")
         |> push_navigate(to: ~p"/management/drivers/#{driver}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_driver(socket, :edit, params) do
    case Drivers.update_driver(socket.assigns.current_scope, socket.assigns.driver, params) do
      {:ok, driver} ->
        {:noreply,
         socket
         |> put_flash(:info, "運転者を更新しました")
         |> push_navigate(to: ~p"/management/drivers/#{driver}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.form for={@form} id="driver-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.section_card title="基本情報">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input field={@form[:code]} type="text" label="運転者コード *" />
            <.input
              field={@form[:employment_type]}
              type="select"
              label="雇用区分 *"
              prompt="選択してください"
              options={Labels.employment_type_options()}
            />
            <.input field={@form[:name]} type="text" label="氏名 *" />
            <.input field={@form[:name_kana]} type="text" label="氏名かな *" />
            <.input field={@form[:hired_on]} type="date" label="入社年月日 *" />
            <.input field={@form[:retired_on]} type="date" label="退職年月日" />
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
          </div>
        </.section_card>

        <.section_card title="免許情報">
          <p
            :if={@license_warning}
            class="text-body-sm mb-4 rounded-md bg-accent-orange px-4 py-3 text-on-primary"
          >
            {@license_warning}
          </p>

          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input field={@form[:license_number]} type="text" label="免許証番号 *" />
            <.input field={@form[:license_expires_on]} type="date" label="免許証有効期限 *" />
          </div>

          <fieldset class="mt-4">
            <legend class="text-eyebrow text-ink-muted">免許種類 *</legend>
            <input type="hidden" name="driver[license_types][]" value="" />
            <div class="mt-2 flex flex-wrap gap-4">
              <label
                :for={{label, value} <- Labels.license_type_options()}
                class="text-body-sm flex items-center gap-2 text-ink-secondary"
              >
                <input
                  type="checkbox"
                  name="driver[license_types][]"
                  value={value}
                  checked={to_string(value) in selected_license_types(@form)}
                  class="size-4 rounded-xs border-hairline text-primary focus:ring-primary"
                />
                {label}
              </label>
            </div>
            <p
              :for={msg <- license_type_errors(@form)}
              class="text-caption mt-2 text-accent-orange-deep"
            >
              免許種類{msg}
            </p>
          </fieldset>
        </.section_card>

        <.section_card title="アカウント">
          <p class="text-body-sm mb-4 text-ink-muted">
            紐付けると、この運転者本人が日報を入力できるようになります。
          </p>
          <.input
            field={@form[:user_id]}
            type="select"
            label="紐付けるアカウント"
            prompt="紐付けない"
            options={Enum.map(@users, &{"#{&1.name}（#{&1.email}）", &1.id})}
          />
        </.section_card>

        <.section_card title="備考">
          <.input field={@form[:note]} type="textarea" label="備考" />
        </.section_card>

        <div class="flex flex-col gap-3 sm:flex-row sm:justify-end">
          <.link
            navigate={cancel_path(@live_action, @driver)}
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

  # チェックボックスを全解除した場合に送られてくる空文字を取り除く
  defp normalize(params) do
    Map.update(params, "license_types", [], fn types ->
      types |> List.wrap() |> Enum.reject(&(&1 == ""))
    end)
  end

  defp selected_license_types(form) do
    form[:license_types].value
    |> List.wrap()
    |> Enum.map(&to_string/1)
  end

  defp license_type_errors(form) do
    Enum.map(form[:license_types].errors, fn {msg, _opts} -> msg end)
  end

  defp cancel_path(:new, _driver), do: ~p"/management/drivers"
  defp cancel_path(:edit, driver), do: ~p"/management/drivers/#{driver}"

  defp assign_form(socket, changeset) do
    socket
    |> assign(form: to_form(changeset, as: :driver))
    |> assign(license_warning: license_warning(changeset))
  end

  # V-6: 免許証有効期限が過去日・30日以内でも保存できるが、警告を表示する
  defp license_warning(changeset) do
    case ConvertDatetime.days_until(Ecto.Changeset.get_field(changeset, :license_expires_on)) do
      nil -> nil
      days when days < 0 -> "免許証の有効期限が#{abs(days)}日超過しています。内容を確認してください。"
      days when days <= 30 -> "免許証の有効期限まであと#{days}日です。"
      _days -> nil
    end
  end
end
