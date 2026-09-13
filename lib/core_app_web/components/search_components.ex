defmodule CoreAppWeb.SearchComponents do
  @moduledoc "一覧画面の絞り込みフォームのコンポーネント"
  use Phoenix.Component

  import CoreAppWeb.CoreComponents, only: [icon: 1]

  @doc """
  検索ボックスと絞り込み項目を並べたバーです。

  `phx-change` で親のLiveViewに条件を渡します。
  """
  attr :id, :string, default: "search-bar"
  attr :params, :map, required: true
  attr :placeholder, :string, default: "検索"
  attr :change, :string, default: "filter"
  slot :filters

  def search_bar(assigns) do
    ~H"""
    <form
      id={@id}
      phx-change={@change}
      phx-submit={@change}
      class="flex flex-col gap-3 rounded-lg border border-hairline bg-surface p-4 lg:flex-row lg:items-end"
    >
      <div class="lg:w-72">
        <label class="text-eyebrow text-ink-muted" for={"#{@id}-q"}>キーワード</label>
        <div class="relative mt-1">
          <.icon
            name="hero-magnifying-glass"
            class="pointer-events-none absolute top-1/2 left-2 size-4 -translate-y-1/2 text-ink-faint"
          />
          <input
            type="search"
            id={"#{@id}-q"}
            name="q"
            value={@params["q"]}
            placeholder={@placeholder}
            phx-debounce="300"
            class="text-body-sm w-full rounded-xs border border-hairline bg-surface py-2 pr-2 pl-8 text-ink placeholder:text-ink-faint focus:border-primary focus:outline-none"
          />
        </div>
      </div>

      {render_slot(@filters)}
    </form>
    """
  end

  @doc """
  絞り込み用のセレクトボックスです。
  """
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, default: nil
  attr :options, :list, required: true, doc: "{表示名, 値} のリスト"
  attr :prompt, :string, default: "すべて"

  def filter_select(assigns) do
    ~H"""
    <div class="lg:w-44">
      <label class="text-eyebrow text-ink-muted" for={"filter-#{@name}"}>{@label}</label>
      <select
        id={"filter-#{@name}"}
        name={@name}
        class="text-body-sm mt-1 w-full rounded-xs border border-hairline bg-surface px-2 py-2 text-ink focus:border-primary focus:outline-none"
      >
        <option value="">{@prompt}</option>
        <option
          :for={{label, value} <- @options}
          value={value}
          selected={to_string(@value) == to_string(value)}
        >
          {label}
        </option>
      </select>
    </div>
    """
  end

  @doc """
  絞り込み用のチェックボックスです。
  """
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :checked, :boolean, default: false
  attr :checked_value, :string, default: "true"

  def filter_checkbox(assigns) do
    ~H"""
    <label class="text-body-sm flex items-center gap-2 text-ink-secondary lg:pb-2">
      <input type="hidden" name={@name} value="" />
      <input
        type="checkbox"
        name={@name}
        value={@checked_value}
        checked={@checked}
        class="size-4 rounded-xs border-hairline text-primary focus:ring-primary"
      />
      {@label}
    </label>
    """
  end
end
