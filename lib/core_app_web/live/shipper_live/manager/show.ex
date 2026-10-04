defmodule CoreAppWeb.ShipperLive.Manager.Show do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Shippers

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    shipper = Shippers.get_shipper!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(shipper: shipper)
     |> assign(page_title: shipper.name)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          navigate={~p"/management/shippers/#{@shipper}/edit"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          編集
        </.link>
      </:actions>

      <div class="space-y-6">
        <.link
          navigate={~p"/management/shippers"}
          class="text-body-sm inline-flex items-center gap-1 text-ink-muted hover:text-primary"
        >
          <.icon name="hero-arrow-left" class="size-4" /> 荷主一覧へ戻る
        </.link>

        <.section_card title="基本情報">
          <:actions>
            <.status_badge status={@shipper.status} type={:shipper} />
          </:actions>
          <.definition_list>
            <:item label="荷主名">{@shipper.name}</:item>
            <:item label="コード">{@shipper.code || "-"}</:item>
            <:item label="拠点">{@shipper.office.name}</:item>
          </.definition_list>
        </.section_card>

        <.section_card title="備考">
          <p class="text-body-sm whitespace-pre-wrap text-ink-secondary">
            {@shipper.note || "-"}
          </p>
        </.section_card>
      </div>
    </Layouts.app>
    """
  end
end
