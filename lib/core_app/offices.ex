defmodule CoreApp.Offices do
  @moduledoc """
  The Offices context.
  """

  import Ecto.Query, warn: false
  alias CoreApp.Repo

  alias CoreApp.Offices.Office

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
end
