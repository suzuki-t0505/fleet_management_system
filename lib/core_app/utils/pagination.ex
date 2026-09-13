defmodule CoreApp.Utils.Pagination do
  @moduledoc """
  一覧クエリをページネーションするモジュールです。

  Context の `list_*` 関数はこの構造体を返します。全件をメモリに読み込まないため、
  一覧クエリは必ずこのモジュールを経由してください。
  """

  import Ecto.Query, warn: false

  defstruct entries: [], page_number: 1, page_size: 50, total_entries: 0, total_pages: 0

  @default_page_size 50
  @max_page_size 100

  @doc """
  クエリをページネーションして `%Pagination{}` を返します。

  ## params
  - `page` ページ番号（1始まり。範囲外は最初または最後のページに丸める）
  - `page_size` 1ページの件数（既定 #{@default_page_size}、上限 #{@max_page_size}）
  """
  def paginate(query, params \\ %{}, repo \\ CoreApp.Repo) do
    page_size = page_size(params)
    total_entries = total_entries(query, repo)
    total_pages = total_pages(total_entries, page_size)
    page_number = page_number(params, total_pages)

    entries =
      query
      |> limit(^page_size)
      |> offset(^((page_number - 1) * page_size))
      |> repo.all()

    %__MODULE__{
      entries: entries,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    }
  end

  @doc """
  前のページがあるかを返します。
  """
  def previous_page?(%__MODULE__{page_number: page_number}), do: page_number > 1

  @doc """
  次のページがあるかを返します。
  """
  def next_page?(%__MODULE__{page_number: page_number, total_pages: total_pages}) do
    page_number < total_pages
  end

  @doc """
  現在のページに表示している範囲（開始位置, 終了位置）を返します。
  """
  def range(%__MODULE__{total_entries: 0}), do: {0, 0}

  def range(%__MODULE__{} = pagination) do
    first = (pagination.page_number - 1) * pagination.page_size + 1

    {first, first + length(pagination.entries) - 1}
  end

  defp total_entries(query, repo) do
    query
    |> exclude(:order_by)
    |> exclude(:preload)
    |> exclude(:select)
    |> repo.aggregate(:count)
  end

  defp total_pages(0, _page_size), do: 1

  defp total_pages(total_entries, page_size) do
    ceil(total_entries / page_size)
  end

  defp page_size(params) do
    params
    |> param(["page_size"])
    |> to_positive_integer(@default_page_size)
    |> min(@max_page_size)
  end

  defp page_number(params, total_pages) do
    params
    |> param(["page"])
    |> to_positive_integer(1)
    |> min(total_pages)
  end

  defp param(params, keys) do
    Enum.find_value(keys, fn key -> params[key] end)
  end

  defp to_positive_integer(nil, default), do: default

  defp to_positive_integer(value, default) when is_integer(value) do
    if value > 0, do: value, else: default
  end

  defp to_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _rest} when parsed > 0 -> parsed
      _other -> default
    end
  end

  defp to_positive_integer(_value, default), do: default
end
