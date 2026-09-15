defmodule CoreApp.Utils.Storage.Gcs do
  @moduledoc """
  添付ファイルを Cloud Storage に保存するアダプタです。本番で使います。

  認証は `goth`（Cloud Run のサービスアカウント）で行い、バケットは
  `config :core_app, :storage, bucket: "..."` で指定します。

  アップロードは**単純アップロード**（`uploadType=media`）で行います。生成クライアントの
  `storage_objects_insert_simple/7`（`uploadType=multipart`）は使いません。`google_gax` が
  `Tesla.Multipart` にフィールド名をアトムで渡すため、マルチパート境界の検証が入った
  tesla では `FunctionClauseError` になるためです（`google_gax` は更新が止まっており、
  最新の 0.4.1 でも同じ）。オブジェクト名は `name` クエリ、MIMEタイプは `Content-Type`
  ヘッダで指定するため、単純アップロードでも必要な情報は揃います。

  > **未検証**: 開発環境にサービスアカウントの認証情報が無いため、`read/1` と `delete/1` は
  > 実行経路を確認していません。自動テストはローカルアダプタに対して書いています。
  """
  @behaviour CoreApp.Utils.Storage

  alias CoreApp.Utils.Storage
  alias GoogleApi.Gax.Request
  alias GoogleApi.Gax.Response
  alias GoogleApi.Storage.V1.Api.Objects
  alias GoogleApi.Storage.V1.Connection
  alias GoogleApi.Storage.V1.Model.Object

  @impl CoreApp.Utils.Storage
  def put(key, source_path, content_type) do
    # ファイル全体をメモリに読み込む。サイズの上限は `Attachments` が保存前に検証している。
    with {:ok, connection} <- connection(),
         {:ok, data} <- File.read(source_path),
         {:ok, _object} <-
           connection
           |> Connection.execute(insert_request(key, content_type, data))
           |> Response.decode(struct: %Object{}) do
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

  defp insert_request(key, content_type, data) do
    Request.new()
    |> Request.method(:post)
    |> Request.url("/upload/storage/v1/b/{bucket}/o", %{
      "bucket" => URI.encode(bucket(), &URI.char_unreserved?/1)
    })
    |> Request.add_param(:query, :uploadType, "media")
    |> Request.add_param(:query, :name, key)
    |> Request.add_param(:header, "content-type", content_type)
    |> Request.add_param(:body, :body, data)
  end

  defp connection do
    with {:ok, token} <- Goth.fetch(CoreApp.Goth) do
      {:ok, Connection.new(token.token)}
    end
  end

  defp bucket, do: Storage.config(:bucket) || raise("storage bucket is not configured")
end
