defmodule CoreAppWeb.TableComponents do
  @moduledoc "一覧テーブルのコンポーネント。PCではテーブル、モバイルではカードで表示する"
  use Phoenix.Component

  @doc """
  一覧テーブルを表示します。

  `lg` 未満の画面では、各行を見出し付きのカードとして縦に並べます。

  ```heex
  <.data_table rows={@page.entries} row_click={&JS.navigate(~p"/vehicles/\#{&1}")}>
    <:col :let={vehicle} label="車両番号">{vehicle.plate_number}</:col>
  </.data_table>
  ```
  """
  attr :id, :string, default: nil
  attr :rows, :list, required: true
  attr :row_click, :any, default: nil, doc: "行クリック時のJSコマンドを返す関数"
  attr :row_id, :any, default: nil

  slot :col, required: true do
    attr :label, :string, required: true
    attr :class, :string
  end

  def data_table(assigns) do
    ~H"""
    <div id={@id}>
      <%!-- PC: テーブル --%>
      <div class="hidden overflow-x-auto rounded-lg border border-hairline bg-surface lg:block">
        <table class="w-full">
          <thead>
            <tr>
              <th
                :for={col <- @col}
                class="text-eyebrow bg-canvas-soft px-4 py-3 text-left text-ink-muted"
              >
                {col[:label]}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={row <- @rows}
              id={@row_id && @row_id.(row)}
              class={["border-t border-hairline", @row_click && "cursor-pointer hover:bg-canvas-soft"]}
              phx-click={@row_click && @row_click.(row)}
            >
              <td
                :for={col <- @col}
                class={["text-body-sm px-4 py-3 text-ink-secondary", col[:class]]}
              >
                {render_slot(col, row)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- モバイル: カード --%>
      <div class="space-y-3 lg:hidden">
        <div
          :for={row <- @rows}
          id={@row_id && "card-#{@row_id.(row)}"}
          class={[
            "rounded-lg border border-hairline bg-surface p-4",
            @row_click && "cursor-pointer"
          ]}
          phx-click={@row_click && @row_click.(row)}
        >
          <dl class="space-y-2">
            <div :for={col <- @col} class="flex items-start justify-between gap-3">
              <dt class="text-eyebrow shrink-0 text-ink-muted">{col[:label]}</dt>
              <dd class="text-body-sm min-w-0 text-right text-ink-secondary">
                {render_slot(col, row)}
              </dd>
            </div>
          </dl>
        </div>
      </div>
    </div>
    """
  end
end
