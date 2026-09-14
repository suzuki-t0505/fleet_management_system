defmodule CoreApp.Offices do
  @moduledoc """
  The Offices context.
  """

  import Ecto.Query, warn: false
  alias CoreApp.Repo

  alias CoreApp.Offices.Office

  alias CoreApp.Accounts.Scope
  alias CoreApp.Utils.Pagination

  @doc """
  ページネーションに対応した拠点を取得します。拠点コードの昇順で返します。

  管理画面用のため、無効化した拠点も扱えます。参照できるのは管理者だけです。

  ## params
  - `q` 検索ワード（拠点コード、拠点名）
  - `active` 有効フラグ。未指定時は有効な拠点のみ、`all` を指定すると無効な拠点を含む
  - `page` / `page_size` ページネーション
  """
  def list_offices(%Scope{role: :admin} = _scope, params \\ %{}) do
    Office
    |> filter_by_active(params["active"])
    |> search(params["q"])
    |> order_by([o], asc: o.code)
    |> Pagination.paginate(params, Repo)
  end

  @doc """
  有効な拠点をすべて取得します。拠点コードの昇順で返します。

  拠点はロールに関わらず選択肢として必要になるため、この関数はスコープを取りません。
  """
  def all_offices do
    Office
    |> where([o], o.active == true)
    |> order_by([o], asc: o.code)
    |> Repo.all()
  end

  @doc """
  IDで拠点を取得します。存在しない場合は `Ecto.NoResultsError` を発生させます。
  """
  def get_office!(<<_::208>> = id), do: Repo.get!(Office, id)

  @doc """
  拠点コードで拠点を取得します。存在しない場合は `nil` を返します。
  """
  def get_office_by_code(code) when is_binary(code), do: Repo.get_by(Office, code: code)

  @doc """
  拠点を作成します。
  """
  def create_office(attrs \\ %{}) do
    %Office{}
    |> Office.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  拠点を更新します。
  """
  def update_office(%Office{} = office, attrs) do
    office
    |> Office.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  拠点のchangesetを取得します。
  """
  def change_office(%Office{} = office, attrs \\ %{}) do
    Office.changeset(office, attrs)
  end

  defp filter_by_active(query, "all"), do: query

  defp filter_by_active(query, "false"), do: where(query, [o], o.active == false)

  defp filter_by_active(query, _active), do: where(query, [o], o.active == true)

  defp search(query, keyword) when is_binary(keyword) and keyword != "" do
    pattern = "%#{String.trim(keyword)}%"

    where(query, [o], ilike(o.code, ^pattern) or ilike(o.name, ^pattern))
  end

  defp search(query, _keyword), do: query
end
