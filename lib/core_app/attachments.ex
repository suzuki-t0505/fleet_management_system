defmodule CoreApp.Attachments do
  @moduledoc """
  The Attachments context.

  車両・点検整備・事故ヒヤリに共通の添付ファイルを扱います。実体は
  `CoreApp.Utils.Storage` が保存し、このContextはメタデータと検証を担当します。

  参照できるかどうかは**対象のContextが判定する**ため、このContextは対象の種別とIDを
  そのまま受け取ります。呼び出し側は、対象をスコープ付きで取得してから渡してください。
  """

  import Ecto.Query, warn: false
  alias CoreApp.Repo

  alias CoreApp.Attachments.Attachment

  alias CoreApp.Accounts.Scope
  alias CoreApp.Utils.Storage

  # V-28: 1記録あたりの上限
  @max_files 10
  @max_bytes 10 * 1024 * 1024

  @doc """
  1つの記録に添付できるファイル数の上限を返します。
  """
  def max_files, do: @max_files

  @doc """
  1ファイルあたりのサイズの上限（バイト）を返します。
  """
  def max_bytes, do: @max_bytes

  @doc """
  対象に紐づく添付ファイルを古い順に取得します。
  """
  def all_attachments_for(attachable_type, <<_::208>> = attachable_id) do
    Attachment
    |> where([a], a.attachable_type == ^attachable_type and a.attachable_id == ^attachable_id)
    |> order_by([a], asc: a.inserted_at, asc: a.id)
    |> Repo.all()
  end

  @doc """
  対象に紐づく添付ファイルの件数を返します。
  """
  def count_attachments_for(attachable_type, <<_::208>> = attachable_id) do
    Attachment
    |> where([a], a.attachable_type == ^attachable_type and a.attachable_id == ^attachable_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  IDで添付ファイルを取得します。

  参照できるかどうかは対象のContextが判定するため、この関数は認可を行いません。
  """
  def get_attachment!(<<_::208>> = id), do: Repo.get!(Attachment, id)

  @doc """
  添付ファイルを保存します（V-28）。

  形式は**先頭バイト**で判定し、拡張子や送信された MIMEタイプは信用しません。
  件数・サイズの上限を超える場合は保存せずにエラーを返します。

  ## attrs
  - `path` アップロードされた一時ファイルのパス
  - `filename` 元のファイル名
  - `byte_size` ファイルサイズ

  ```elixir
  iex> create_attachment(scope, {:incident, incident.id}, attrs)
  {:ok, %Attachment{}}
  ```
  """
  def create_attachment(%Scope{} = scope, {attachable_type, attachable_id}, attrs) do
    with :ok <- ensure_within_limit(attachable_type, attachable_id),
         :ok <- ensure_within_size(attrs.byte_size),
         {:ok, content_type} <- detect_content_type(attrs.path),
         key <- storage_key(attachable_type, attachable_id, attrs.filename),
         :ok <- Storage.put(key, attrs.path, content_type) do
      %Attachment{}
      |> Attachment.changeset(%{
        attachable_type: attachable_type,
        attachable_id: attachable_id,
        filename: attrs.filename,
        content_type: content_type,
        byte_size: attrs.byte_size,
        storage_key: key,
        uploaded_by_user_id: scope.user.id
      })
      |> Repo.insert()
    end
  end

  @doc """
  添付ファイルの内容を読み出します。
  """
  def read_attachment(%Attachment{} = attachment) do
    Storage.read(attachment.storage_key)
  end

  @doc """
  添付ファイルのレコードを削除します。

  保存先の実体は消しません（architecture.md 4.4）。誤操作からの復旧のため、
  実体はバケットのライフサイクルに任せます。
  """
  def delete_attachment(%Scope{} = _scope, %Attachment{} = attachment) do
    Repo.delete(attachment)
  end

  defp ensure_within_limit(attachable_type, attachable_id) do
    if count_attachments_for(attachable_type, attachable_id) < @max_files do
      :ok
    else
      {:error, :too_many_files}
    end
  end

  defp ensure_within_size(byte_size) when byte_size > @max_bytes, do: {:error, :too_large}
  defp ensure_within_size(_byte_size), do: :ok

  # 拡張子は偽装できるため、先頭バイトで形式を判定する
  defp detect_content_type(path) do
    with {:ok, file} <- File.open(path, [:read, :binary]),
         header <- IO.binread(file, 8),
         :ok <- File.close(file) do
      case Attachment.content_type_of(to_binary(header)) do
        {:ok, content_type} -> {:ok, content_type}
        :error -> {:error, :unsupported_type}
      end
    end
  end

  defp to_binary(header) when is_binary(header), do: header
  defp to_binary(_header), do: ""

  # architecture.md 4.4: attachments/{attachable_type}/{attachable_id}/{ULID}_{元ファイル名}
  defp storage_key(attachable_type, attachable_id, filename) do
    Path.join([
      "attachments",
      to_string(attachable_type),
      attachable_id,
      "#{Ecto.ULID.generate()}_#{Path.basename(filename)}"
    ])
  end
end
