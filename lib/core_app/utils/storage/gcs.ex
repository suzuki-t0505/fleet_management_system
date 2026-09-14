defmodule CoreApp.Utils.Storage.Gcs do
  @moduledoc """
  添付ファイルを Cloud Storage に保存するアダプタです。本番で使います。

  認証は `goth`（Cloud Run のサービスアカウント）で行い、バケットは
  `config :core_app, :storage, bucket: "..."` で指定します。

  > **未検証**: 開発環境にサービスアカウントの認証情報が無いため、このアダプタは
  > 実行経路を確認していません。本番設定を投入する際に疎通確認が必要です。
  > 自動テストはローカルアダプタに対して書いています。
  """
  @behaviour CoreApp.Utils.Storage

  alias CoreApp.Utils.Storage
  alias GoogleApi.Storage.V1.Api.Objects
  alias GoogleApi.Storage.V1.Connection

  @impl CoreApp.Utils.Storage
  def put(key, source_path, content_type) do
    with {:ok, connection} <- connection(),
         {:ok, _object} <-
           Objects.storage_objects_insert_simple(
             connection,
             bucket(),
             "multipart",
             %{name: key, contentType: content_type},
             source_path
           ) do
      :ok
    end
  end

  @impl CoreApp.Utils.Storage
  def read(key) do
    with {:ok, connection} <- connection(),
         {:ok, response} <-
           Objects.storage_objects_get(connection, bucket(), key, [alt: "media"], decode: false) do
      {:ok, response.body}
    end
  end

  @impl CoreApp.Utils.Storage
  def delete(key) do
    with {:ok, connection} <- connection(),
         {:ok, _empty} <- Objects.storage_objects_delete(connection, bucket(), key) do
      :ok
    end
  end

  defp connection do
    with {:ok, token} <- Goth.fetch(CoreApp.Goth) do
      {:ok, Connection.new(token.token)}
    end
  end

  defp bucket, do: Storage.config(:bucket) || raise("storage bucket is not configured")
end
