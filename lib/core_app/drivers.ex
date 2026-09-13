defmodule CoreApp.Drivers do
  @moduledoc """
  The Drivers context.
  """

  import Ecto.Query, warn: false
  alias CoreApp.Repo
  alias Ecto.Multi

  alias CoreApp.Drivers.Driver

  alias CoreApp.Accounts.Scope
  alias CoreApp.Accounts.User
  alias CoreApp.AuditLogs
  alias CoreApp.Utils.Pagination

  @resource_type "driver"

  @doc """
  ページネーションに対応した運転者を取得します。氏名かなの昇順で返します。

  スコープが管理者以外の場合、所属拠点の運転者のみを返します。

  ## params
  - `q` 検索ワード（氏名、氏名かな、運転者コード）
  - `office_id` 拠点ID（管理者のみ有効）
  - `employment_type` 雇用区分。未指定時は退職者を除外し、`all` を指定すると退職者を含む
  - `page` ページ番号
  - `page_size` 取得するデータ数
  """
  def list_drivers(%Scope{} = scope, params \\ %{}) do
    Driver
    |> scoped(scope)
    |> filter_by_office(scope, params["office_id"])
    |> filter_by_employment_type(params["employment_type"])
    |> search(params["q"])
    |> order_by([d], asc: d.name_kana)
    |> preload([:office, :user])
    |> Pagination.paginate(params, Repo)
  end

  @doc """
  運行日報などの選択肢に出せる運転者（退職者を除く）をすべて取得します。
  """
  def all_selectable_drivers(%Scope{} = scope) do
    Driver
    |> scoped(scope)
    |> where([d], d.employment_type != :retired)
    |> order_by([d], asc: d.name_kana)
    |> Repo.all()
  end

  @doc """
  IDで運転者を取得します。

  スコープの範囲外（他拠点）の運転者は存在しないものとして扱い、`Ecto.NoResultsError` を
  発生させます。
  """
  def get_driver!(%Scope{} = scope, <<_::208>> = id) do
    Driver
    |> scoped(scope)
    |> preload([:office, :user])
    |> Repo.get!(id)
  end

  @doc """
  利用者に紐付く運転者を取得します。紐付いていない場合は `nil` を返します。
  """
  def get_driver_by_user(<<_::208>> = user_id) do
    Repo.get_by(Driver, user_id: user_id)
  end

  @doc """
  雇用区分ごとの人数を返します。退職者は含みません。
  """
  def count_drivers_by_employment_type(%Scope{} = scope) do
    Driver
    |> scoped(scope)
    |> where([d], d.employment_type != :retired)
    |> group_by([d], d.employment_type)
    |> select([d], {d.employment_type, count(d.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  運転者に紐付けられる利用者を取得します。

  対象は運転者と同じ拠点の有効なアカウントのうち、他の運転者に紐付いていないものです。
  編集中の運転者自身に紐付いているアカウントは候補に含めます。
  """
  def all_linkable_users(%Scope{} = scope, driver \\ nil) do
    office_id = linkable_office_id(scope, driver)
    linked_user_ids = linked_user_ids(driver)

    User
    |> where([u], u.office_id == ^office_id and u.active == true)
    |> where([u], u.id not in ^linked_user_ids)
    |> order_by([u], asc: u.name)
    |> Repo.all()
  end

  @doc """
  運転者を登録し、監査ログを同一トランザクションで記録します。
  """
  def create_driver(%Scope{} = scope, attrs \\ %{}, opts \\ []) do
    changeset = Driver.changeset(%Driver{}, put_office_id(scope, attrs))

    Multi.new()
    |> Multi.insert(:driver, changeset)
    |> AuditLogs.record_multi(
      :audit_log,
      scope,
      :create,
      &{@resource_type, &1.driver, changeset},
      opts
    )
    |> Repo.transaction()
    |> normalize_transaction()
  end

  @doc """
  運転者を更新し、監査ログを同一トランザクションで記録します。

  退職も雇用区分の変更として扱います。運転者の物理削除は提供しません。
  """
  def update_driver(%Scope{} = scope, %Driver{} = driver, attrs, opts \\ []) do
    changeset = Driver.changeset(driver, put_office_id(scope, attrs))

    Multi.new()
    |> Multi.update(:driver, changeset)
    |> AuditLogs.record_multi(
      :audit_log,
      scope,
      :update,
      &{@resource_type, &1.driver, changeset},
      opts
    )
    |> Repo.transaction()
    |> normalize_transaction()
  end

  @doc """
  運転者のchangesetを取得します。
  """
  def change_driver(%Driver{} = driver, attrs \\ %{}) do
    Driver.changeset(driver, attrs)
  end

  defp scoped(query, %Scope{role: :admin}), do: query

  defp scoped(query, %Scope{office_id: office_id}) do
    where(query, [d], d.office_id == ^office_id)
  end

  # 運行管理者は自拠点に強制する。管理者のみ拠点を指定できる。
  defp put_office_id(%Scope{role: :admin}, attrs), do: attrs

  defp put_office_id(%Scope{office_id: office_id}, attrs) do
    Map.put(attrs, "office_id", office_id)
  end

  # 管理者が他拠点の運転者を編集する場合、その運転者の拠点の利用者を候補にする。
  defp linkable_office_id(%Scope{role: :admin} = scope, driver) do
    if driver && driver.office_id, do: driver.office_id, else: scope.office_id
  end

  defp linkable_office_id(%Scope{office_id: office_id}, _driver), do: office_id

  defp linked_user_ids(driver) do
    query = where(Driver, [d], not is_nil(d.user_id))

    query =
      if driver && driver.id do
        where(query, [d], d.id != ^driver.id)
      else
        query
      end

    query |> select([d], d.user_id) |> Repo.all()
  end

  defp filter_by_office(query, %Scope{role: :admin}, office_id)
       when is_binary(office_id) and office_id != "" do
    where(query, [d], d.office_id == ^office_id)
  end

  defp filter_by_office(query, _scope, _office_id), do: query

  defp filter_by_employment_type(query, "all"), do: query

  defp filter_by_employment_type(query, employment_type)
       when is_binary(employment_type) and employment_type != "" do
    where(query, [d], d.employment_type == ^employment_type)
  end

  defp filter_by_employment_type(query, _employment_type) do
    where(query, [d], d.employment_type != :retired)
  end

  defp search(query, keyword) when is_binary(keyword) and keyword != "" do
    pattern = "%#{String.trim(keyword)}%"

    where(
      query,
      [d],
      ilike(d.name, ^pattern) or ilike(d.name_kana, ^pattern) or ilike(d.code, ^pattern)
    )
  end

  defp search(query, _keyword), do: query

  defp normalize_transaction({:ok, %{driver: driver}}), do: {:ok, driver}
  defp normalize_transaction({:error, :driver, changeset, _changes}), do: {:error, changeset}
end
