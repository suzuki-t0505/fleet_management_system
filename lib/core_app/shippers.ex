defmodule CoreApp.Shippers do
  @moduledoc """
  The Shippers context.

  荷主（配車の取引先）のマスタを管理します。物理削除は提供せず、無効化で運用します。
  """

  import Ecto.Query, warn: false
  alias CoreApp.Repo
  alias Ecto.Multi

  alias CoreApp.Shippers.Shipper

  alias CoreApp.Accounts.Scope
  alias CoreApp.AuditLogs
  alias CoreApp.Utils.Pagination

  @resource_type "shipper"

  @doc """
  ページネーションに対応した荷主を取得します。荷主名の昇順で返します。

  スコープが管理者以外の場合、所属拠点の荷主のみを返します。

  ## params
  - `q` 検索ワード（荷主名、コード）
  - `office_id` 拠点ID（管理者のみ有効）
  - `status` ステータス。未指定時は有効のみ、`all` を指定すると無効を含む
  - `page` / `page_size` ページネーション
  """
  def list_shippers(%Scope{} = scope, params \\ %{}) do
    Shipper
    |> scoped(scope)
    |> filter_by_office(scope, params["office_id"])
    |> filter_by_status(params["status"])
    |> search(params["q"])
    |> order_by([s], asc: s.name)
    |> preload(:office)
    |> Pagination.paginate(params, Repo)
  end

  @doc """
  他機能の選択肢に出せる荷主（有効のみ）をすべて取得します。

  `current_id` を渡すと、無効化済みでもその荷主を選択肢に含めます（編集時に既存の
  紐付けを失わないため）。
  """
  def all_selectable_shippers(%Scope{} = scope, current_id \\ nil) do
    Shipper
    |> scoped(scope)
    |> active_or_current(current_id)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  defp active_or_current(query, nil), do: where(query, [s], s.status == :active)

  defp active_or_current(query, current_id) do
    where(query, [s], s.status == :active or s.id == ^current_id)
  end

  @doc """
  IDで荷主を取得します。

  スコープの範囲外（他拠点）の荷主は存在しないものとして扱い、`Ecto.NoResultsError` を
  発生させます。
  """
  def get_shipper!(%Scope{} = scope, <<_::208>> = id) do
    Shipper
    |> scoped(scope)
    |> preload(:office)
    |> Repo.get!(id)
  end

  @doc """
  荷主を登録し、監査ログを同一トランザクションで記録します。
  """
  def create_shipper(%Scope{} = scope, attrs \\ %{}, opts \\ []) do
    changeset = Shipper.changeset(%Shipper{}, put_office_id(scope, attrs))

    Multi.new()
    |> Multi.insert(:shipper, changeset)
    |> AuditLogs.record_multi(
      :audit_log,
      scope,
      :create,
      &{@resource_type, &1.shipper, changeset},
      opts
    )
    |> Repo.transaction()
    |> normalize_transaction()
  end

  @doc """
  荷主を更新し、監査ログを同一トランザクションで記録します。

  無効化もこの関数で行います。荷主の物理削除は提供しません。
  """
  def update_shipper(%Scope{} = scope, %Shipper{} = shipper, attrs, opts \\ []) do
    changeset = Shipper.changeset(shipper, put_office_id(scope, attrs))

    Multi.new()
    |> Multi.update(:shipper, changeset)
    |> AuditLogs.record_multi(
      :audit_log,
      scope,
      :update,
      &{@resource_type, &1.shipper, changeset},
      opts
    )
    |> Repo.transaction()
    |> normalize_transaction()
  end

  @doc """
  荷主のchangesetを取得します。
  """
  def change_shipper(%Shipper{} = shipper, attrs \\ %{}) do
    Shipper.changeset(shipper, attrs)
  end

  defp scoped(query, %Scope{role: :admin}), do: query

  defp scoped(query, %Scope{office_id: office_id}) do
    where(query, [s], s.office_id == ^office_id)
  end

  # 運行管理者は自拠点に強制する。管理者のみ拠点を指定できる。
  defp put_office_id(%Scope{role: :admin}, attrs), do: attrs

  defp put_office_id(%Scope{office_id: office_id}, attrs) do
    Map.put(attrs, "office_id", office_id)
  end

  defp filter_by_office(query, %Scope{role: :admin}, office_id)
       when is_binary(office_id) and office_id != "" do
    where(query, [s], s.office_id == ^office_id)
  end

  defp filter_by_office(query, _scope, _office_id), do: query

  defp filter_by_status(query, "all"), do: query

  defp filter_by_status(query, status) when is_binary(status) and status != "" do
    where(query, [s], s.status == ^status)
  end

  defp filter_by_status(query, _status), do: where(query, [s], s.status == :active)

  defp search(query, keyword) when is_binary(keyword) and keyword != "" do
    pattern = "%#{String.trim(keyword)}%"

    where(query, [s], ilike(s.name, ^pattern) or ilike(s.code, ^pattern))
  end

  defp search(query, _keyword), do: query

  defp normalize_transaction({:ok, %{shipper: shipper}}), do: {:ok, shipper}
  defp normalize_transaction({:error, :shipper, changeset, _changes}), do: {:error, changeset}
end
