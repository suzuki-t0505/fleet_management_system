defmodule CoreApp.Utils.Storage.Gcs do
  @moduledoc """
  添付ファイルを Cloud Storage に保存するアダプタです。本番で使います。

  認証は `goth`（Cloud Run のサービスアカウント）で行い、バケットは
  `config :core_app, :storage, bucket: "..."` で指定します。

  ダウンロードは署名付きURL（V4・5分間有効）で行います。URLの発行前に認可するのは
  呼び出し側（`AttachmentController`）の責務です。署名には IAM の `signBlob` を使うため、
  署名者のサービスアカウント（`config :core_app, :storage, signer_email: "..."`）に
  `roles/iam.serviceAccountTokenCreator` が必要です。

  > **未検証**: 開発環境にサービスアカウントの認証情報が無いため、実行経路は本番でしか
  > 確認できません。自動テストはローカルアダプタに対して書いています。
  """
  @behaviour CoreApp.Utils.Storage

  alias CoreApp.Utils.Storage
  alias GoogleApi.Storage.V1.Api.Objects
  alias GoogleApi.Storage.V1.Connection

  # 署名付きURLの有効期間（秒）
  @expires 300

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

  @impl CoreApp.Utils.Storage
  def signed_url(key) do
    # 実体が無いキーにも署名できてしまうため、先に存在を確かめてから発行する。
    with {:ok, token} <- Goth.fetch(CoreApp.Goth),
         {:ok, signer_email} <- signer_email(),
         {:ok, _object} <- Objects.storage_objects_get(Connection.new(token.token), bucket(), key) do
      config = %GcsSignedUrl.SignBlob.OAuthConfig{
        service_account: signer_email,
        access_token: token.token
      }

      GcsSignedUrl.generate_v4(config, bucket(), key, verb: "GET", expires: @expires)
    end
  end

  defp connection do
    with {:ok, token} <- Goth.fetch(CoreApp.Goth) do
      {:ok, Connection.new(token.token)}
    end
  end

  defp bucket, do: Storage.config(:bucket) || raise("storage bucket is not configured")

  defp signer_email do
    case Storage.config(:signer_email) do
      nil -> {:error, :signer_email_not_configured}
      email -> {:ok, email}
    end
  end
end
