defmodule CoreAppWeb.PaginationComponents do
  @moduledoc "ページネーションのコンポーネント"
  use Phoenix.Component

  alias CoreApp.Utils.Pagination

  @doc """
  ページ送りと表示件数を表示します。
  """
  attr :page, :map, required: true, doc: "%CoreApp.Utils.Pagination{}"
  attr :path, :any, required: true, doc: "ページ番号を受け取りURLを返す関数"

  def pagination(assigns) do
    {first, last} = Pagination.range(assigns.page)
    assigns = assign(assigns, first: first, last: last)

    ~H"""
    <div class="flex flex-col items-center justify-between gap-3 sm:flex-row">
      <p class="text-caption text-ink-muted">
        {@page.total_entries}件中 {@first}〜{@last}件を表示
      </p>

      <nav :if={@page.total_pages > 1} class="flex items-center gap-2">
        <.page_link
          enabled={Pagination.previous_page?(@page)}
          path={@path.(@page.page_number - 1)}
          label="前へ"
        />
        <span class="text-body-sm text-ink-secondary">
          {@page.page_number} / {@page.total_pages}
        </span>
        <.page_link
          enabled={Pagination.next_page?(@page)}
          path={@path.(@page.page_number + 1)}
          label="次へ"
        />
      </nav>
    </div>
    """
  end

  attr :enabled, :boolean, required: true
  attr :path, :string, required: true
  attr :label, :string, required: true

  defp page_link(%{enabled: false} = assigns) do
    ~H"""
    <span class="text-body-sm cursor-not-allowed rounded-md border border-hairline px-3 py-1 text-ink-faint">
      {@label}
    </span>
    """
  end

  defp page_link(assigns) do
    ~H"""
    <.link
      patch={@path}
      class="text-body-sm rounded-md border border-hairline px-3 py-1 text-ink-secondary hover:bg-canvas-soft"
    >
      {@label}
    </.link>
    """
  end
end
