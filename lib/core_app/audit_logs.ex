defmodule CoreApp.AuditLogs do
  @moduledoc """
  The AuditLogs context.

  監査ログは追記専用です。更新・削除の関数は提供しません。
  """

  import Ecto.Query, warn: false
  alias CoreApp.Repo

  alias CoreApp.AuditLogs.AuditLog

  alias CoreApp.Accounts.Scope
  alias CoreApp.Utils.Pagination

  @doc """
  操作を監査ログに記録します。

  台帳の変更は記録対象の保存と同一トランザクションで書く必要があるため、
  通常は `record_multi/5` を使ってください。この関数は単独で記録する場合に使います。
  """
  def record(%Scope{} = scope, action, resource_type, resource, opts \\ []) do
    scope
    |> log_attrs(action, resource_type, resource, opts)
    |> then(&AuditLog.changeset(%AuditLog{}, &1))
    |> Repo.insert()
  end

  @doc """
  `Ecto.Multi` に監査ログの記録を追加します。

  `fun` は直前までの変更マップを受け取り、`{resource_type, resource}` または
  `{resource_type, resource, changeset}` を返します。changeset を渡した場合、その変更差分を
  `changes` に保存します。

  ```elixir
  Ecto.Multi.new()
  |> Ecto.Multi.insert(:vehicle, changeset)
  |> AuditLogs.record_multi(:audit_log, scope, :create, &{"vehicle", &1.vehicle, changeset})
  |> Repo.transaction()
  ```
  """
  def record_multi(multi, name, %Scope{} = scope, action, fun, opts \\ []) do
    Ecto.Multi.insert(multi, name, fn changes ->
      {resource_type, resource, changeset} = normalize(fun.(changes))

      attrs =
        scope
        |> log_attrs(action, resource_type, resource, opts)
        |> Map.put(:changes, changes_of(changeset))

      AuditLog.changeset(%AuditLog{}, attrs)
    end)
  end

  @doc """
  監査ログをページネーション付きで取得します。管理者のみが参照できます。

  ## params
  - `q` 検索ワード（操作者の氏名・メールアドレス）
  - `resource_type` リソース種別
  - `action` 操作
  - `user_id` 操作者
  - `page` / `page_size` ページネーション
  """
  def list_audit_logs(%Scope{role: :admin} = _scope, params \\ %{}) do
    AuditLog
    |> filter_by_resource_type(params["resource_type"])
    |> filter_by_action(params["action"])
    |> filter_by_user(params["user_id"])
    |> search(params["q"])
    |> order_by([l], desc: l.inserted_at, desc: l.id)
    |> preload(:user)
    |> Pagination.paginate(params, Repo)
  end

  @doc """
  リソースに紐づく監査ログを新しい順に取得します。
  """
  def all_audit_logs_for(resource_type, <<_::208>> = resource_id) do
    AuditLog
    |> where([l], l.resource_type == ^resource_type and l.resource_id == ^resource_id)
    |> order_by([l], desc: l.inserted_at, desc: l.id)
    |> preload(:user)
    |> Repo.all()
  end

  defp normalize({resource_type, resource}), do: {resource_type, resource, nil}
  defp normalize({resource_type, resource, changeset}), do: {resource_type, resource, changeset}

  defp log_attrs(%Scope{user: user}, action, resource_type, resource, opts) do
    %{
      user_id: user.id,
      action: action,
      resource_type: resource_type,
      resource_id: resource.id,
      changes: changes_of(opts[:changeset]),
      ip_address: opts[:ip_address]
    }
  end

  defp changes_of(nil), do: nil

  defp changes_of(%Ecto.Changeset{} = changeset) do
    Map.new(changeset.changes, fn {key, value} -> {to_string(key), serialize(value)} end)
  end

  defp serialize(%Date{} = value), do: Date.to_iso8601(value)
  defp serialize(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp serialize(value) when is_atom(value) and not is_boolean(value) and not is_nil(value) do
    to_string(value)
  end

  defp serialize(value), do: value

  defp filter_by_resource_type(query, nil), do: query
  defp filter_by_resource_type(query, ""), do: query

  defp filter_by_resource_type(query, resource_type) do
    where(query, [l], l.resource_type == ^resource_type)
  end

  defp filter_by_user(query, nil), do: query
  defp filter_by_user(query, ""), do: query

  defp filter_by_user(query, user_id) do
    where(query, [l], l.user_id == ^user_id)
  end

  defp filter_by_action(query, nil), do: query
  defp filter_by_action(query, ""), do: query

  defp filter_by_action(query, action) do
    where(query, [l], l.action == ^action)
  end

  defp search(query, keyword) when is_binary(keyword) and keyword != "" do
    pattern = "%#{String.trim(keyword)}%"

    query
    |> join(:inner, [l], u in assoc(l, :user), as: :user)
    |> where([l, user: u], ilike(u.name, ^pattern) or ilike(u.email, ^pattern))
  end

  defp search(query, _keyword), do: query
end
