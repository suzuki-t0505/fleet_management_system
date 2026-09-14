defmodule CoreAppWeb.CardComponents do
  @moduledoc "カード・項目リスト・空状態のコンポーネント"
  use Phoenix.Component

  @doc """
  見出し付きのカードです。詳細画面の区切りに使います。
  """
  attr :title, :string, default: nil
  attr :class, :string, default: nil
  slot :actions
  slot :inner_block, required: true

  def section_card(assigns) do
    ~H"""
    <section class={["rounded-lg border border-hairline bg-surface p-6", @class]}>
      <div :if={@title || @actions != []} class="mb-4 flex items-center gap-3">
        <h2 :if={@title} class="text-title">{@title}</h2>
        <div :if={@actions != []} class="ml-auto flex items-center gap-2">
          {render_slot(@actions)}
        </div>
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  項目名と値の組を並べて表示します。

  ```heex
  <.definition_list>
    <:item label="車名">エルフ</:item>
  </.definition_list>
  ```
  """
  attr :columns, :integer, default: 2

  slot :item do
    attr :label, :string, required: true
  end

  def definition_list(assigns) do
    ~H"""
    <dl class={[
      "grid gap-x-6 gap-y-4",
      @columns == 2 && "grid-cols-1 sm:grid-cols-2",
      @columns == 3 && "grid-cols-1 sm:grid-cols-3",
      @columns == 1 && "grid-cols-1"
    ]}>
      <div :for={item <- @item}>
        <dt class="text-eyebrow text-ink-muted">{item.label}</dt>
        <dd class="text-body-sm text-ink-secondary mt-1">{render_slot(item)}</dd>
      </div>
    </dl>
    """
  end

  @doc """
  データが無いときの表示です。
  """
  attr :message, :string, required: true
  slot :actions

  def empty_state(assigns) do
    ~H"""
    <div class="rounded-lg border border-hairline bg-canvas-soft p-8 text-center">
      <p class="text-body-md text-ink-muted">{@message}</p>
      <div :if={@actions != []} class="mt-4 flex justify-center gap-2">{render_slot(@actions)}</div>
    </div>
    """
  end
end
