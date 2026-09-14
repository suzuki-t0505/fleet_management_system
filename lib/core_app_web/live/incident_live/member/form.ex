defmodule CoreAppWeb.IncidentLive.Member.Form do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Attachments
  alias CoreApp.Incidents
  alias CoreApp.Incidents.Incident
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Vehicles

  alias CoreAppWeb.IncidentLive.Labels

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(vehicles: vehicle_options(socket.assigns.current_scope))
     |> allow_upload(:files,
       accept: accepted_extensions(),
       max_entries: Attachments.max_files(),
       max_file_size: Attachments.max_bytes()
     )
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    scope = socket.assigns.current_scope
    incident = %Incident{driver_id: scope.driver_id}

    socket
    |> assign(page_title: "事故・ヒヤリを報告")
    |> assign(incident: incident)
    |> assign(attachments: [])
    |> assign_form(Incidents.change_incident(incident, scope))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    scope = socket.assigns.current_scope
    incident = Incidents.get_incident!(scope, id)

    socket
    |> assign(page_title: "報告を編集")
    |> assign(incident: incident)
    |> assign(attachments: Attachments.all_attachments_for(:incident, incident.id))
    |> assign_form(Incidents.change_incident(incident, scope))
  end

  @impl true
  def handle_event("validate", %{"incident" => params}, socket) do
    changeset =
      socket.assigns.incident
      |> Incidents.change_incident(socket.assigns.current_scope, params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  def handle_event("delete_attachment", %{"id" => id}, socket) do
    attachment = Attachments.get_attachment!(id)
    {:ok, _deleted} = Attachments.delete_attachment(socket.assigns.current_scope, attachment)

    {:noreply,
     socket
     |> assign(
       attachments: Attachments.all_attachments_for(:incident, socket.assigns.incident.id)
     )
     |> put_flash(:info, "添付ファイルを削除しました")}
  end

  def handle_event("save", %{"incident" => params}, socket) do
    save_incident(socket, socket.assigns.live_action, params)
  end

  defp save_incident(socket, :new, params) do
    case Incidents.create_incident(socket.assigns.current_scope, params) do
      {:ok, incident} ->
        {:noreply,
         socket
         |> consume_attachments(incident)
         |> put_flash(:info, "事故・ヒヤリを報告しました")
         |> push_navigate(to: ~p"/incidents/#{incident}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_incident(socket, :edit, params) do
    scope = socket.assigns.current_scope

    case Incidents.update_incident(scope, socket.assigns.incident, params) do
      {:ok, incident} ->
        {:noreply,
         socket
         |> consume_attachments(incident)
         |> put_flash(:info, "報告を更新しました")
         |> push_navigate(to: ~p"/incidents/#{incident}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "この報告は編集できません")}
    end
  end

  # 記録を保存してから添付を保存する。添付の失敗は報告そのものを取り消さず、警告として伝える。
  defp consume_attachments(socket, incident) do
    scope = socket.assigns.current_scope

    failed =
      socket
      |> consume_uploaded_entries(:files, fn %{path: path}, entry ->
        attrs = %{path: path, filename: entry.client_name, byte_size: entry.client_size}

        {:ok, Attachments.create_attachment(scope, {:incident, incident.id}, attrs)}
      end)
      |> Enum.reject(&match?({:ok, _attachment}, &1))

    if failed == [] do
      socket
    else
      put_flash(socket, :error, "#{length(failed)}件の添付ファイルを保存できませんでした")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.form
        for={@form}
        id="incident-form"
        phx-change="validate"
        phx-submit="save"
        class="mx-auto max-w-2xl space-y-6"
      >
        <.section_card title="発生状況">
          <div class="space-y-4">
            <.input
              field={@form[:occurred_at]}
              type="datetime-local"
              label="発生日時 *"
              value={ConvertDatetime.to_input_value(@form[:occurred_at].value)}
            />
            <.input
              field={@form[:category]}
              type="select"
              label="区分 *"
              prompt="選択してください"
              options={Labels.category_options()}
            />
            <.input
              field={@form[:vehicle_id]}
              type="select"
              label="車両 *"
              prompt="選択してください"
              options={@vehicles}
            />
            <div>
              <p class="text-eyebrow text-ink-muted">運転者</p>
              <p class="text-body-sm mt-2 text-ink-secondary">{driver_name(@current_scope)}</p>
              <.input field={@form[:driver_id]} type="hidden" />
            </div>
            <.input field={@form[:place]} type="text" label="発生場所 *" />
            <.input
              field={@form[:weather]}
              type="select"
              label="天候 *"
              prompt="選択してください"
              options={Labels.weather_options()}
            />
            <.input
              field={@form[:description]}
              type="textarea"
              label="発生状況 *"
              placeholder="何が起きたかを、時系列で具体的に記入してください"
            />
          </div>
        </.section_card>

        <.section_card title="相手方・被害">
          <div class="space-y-4">
            <.input field={@form[:counterpart]} type="textarea" label="相手方の概要" />
            <.input field={@form[:damage]} type="textarea" label="被害・損害の概要" />
            <.input field={@form[:police_reported]} type="checkbox" label="警察に届け出た" />
          </div>
        </.section_card>

        <.section_card title="写真・書類">
          <div class="space-y-4">
            <.attachment_list :if={@attachments != []} attachments={@attachments} deletable />
            <.upload_area upload={@uploads.files} remaining={remaining(@attachments)} />
          </div>
        </.section_card>

        <div class="flex flex-col gap-3 sm:flex-row sm:justify-end">
          <.link
            navigate={cancel_path(@live_action, @incident)}
            class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-center text-ink hover:bg-canvas-soft"
          >
            キャンセル
          </.link>
          <button
            type="submit"
            phx-disable-with="保存中..."
            class="text-button rounded-full bg-primary px-6 py-2 text-on-primary hover:bg-primary-active"
          >
            報告する
          </button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  defp cancel_path(:new, _incident), do: ~p"/incidents"
  defp cancel_path(:edit, incident), do: ~p"/incidents/#{incident}"

  defp remaining(attachments), do: Attachments.max_files() - length(attachments)

  defp driver_name(%{user: %{driver: %{name: name}}}), do: name
  defp driver_name(_scope), do: "（運転者台帳に未登録）"

  defp assign_form(socket, changeset) do
    assign(socket, form: to_form(changeset, as: :incident))
  end

  defp vehicle_options(scope) do
    scope
    |> Vehicles.all_selectable_vehicles()
    |> Enum.map(&{"#{&1.plate_number}（#{&1.model_name}）", &1.id})
  end
end
