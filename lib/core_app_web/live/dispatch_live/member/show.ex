defmodule CoreAppWeb.DispatchLive.Member.Show do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Dispatches

  alias CoreAppWeb.DispatchLive.Detail

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    dispatch = Dispatches.get_dispatch!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(dispatch: dispatch)
     |> assign(page_title: dispatch.title)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="space-y-6">
        <.link
          navigate={~p"/dispatches"}
          class="text-body-sm inline-flex items-center gap-1 text-ink-muted hover:text-primary"
        >
          <.icon name="hero-arrow-left" class="size-4" /> 配車一覧へ戻る
        </.link>

        <Detail.sections dispatch={@dispatch} show_amount={false} />
      </div>
    </Layouts.app>
    """
  end
end
