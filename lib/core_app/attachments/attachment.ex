defmodule CoreApp.Attachments.Attachment do
  @moduledoc false
  use CoreApp.Schema
  import Ecto.Changeset

  alias CoreApp.Accounts.User

  @attachable_types ~w(vehicle maintenance incident)a

  # 受け入れる形式と、先頭バイト（マジックナンバー）の対応
  @signatures [
    {"application/pdf", ".pdf", "%PDF"},
    {"image/png", ".png", <<137, 80, 78, 71, 13, 10, 26, 10>>},
    {"image/jpeg", ".jpg", <<255, 216, 255>>}
  ]

  schema "attachments" do
    field :attachable_type, Ecto.Enum, values: @attachable_types
    field :attachable_id, Ecto.ULID
    field :filename, :string
    field :content_type, :string
    field :byte_size, :integer
    field :storage_key, :string

    belongs_to(:uploaded_by_user, User)

    timestamps(type: :utc_datetime)
  end

  @doc """
  添付できる対象の一覧を返します。
  """
  def attachable_types, do: @attachable_types

  @doc """
  受け入れる MIMEタイプの一覧を返します。
  """
  def content_types,
    do: Enum.map(@signatures, fn {content_type, _ext, _magic} -> content_type end)

  @doc """
  アップロードのフォームで受け入れる拡張子の一覧を返します。
  """
  def extensions, do: ~w(.pdf .png .jpg .jpeg)

  @doc """
  先頭バイトから MIMEタイプを判定します。

  拡張子は偽装できるため、保存する MIMEタイプは常にこの判定結果を使います。
  判定できない形式は `:error` を返します。

  ```elixir
  iex> content_type_of("%PDF-1.7 ...")
  {:ok, "application/pdf"}
  ```
  """
  def content_type_of(binary) when is_binary(binary) do
    Enum.find_value(@signatures, :error, fn {content_type, _ext, magic} ->
      String.starts_with?(binary, magic) && {:ok, content_type}
    end)
  end

  @doc """
  添付ファイルのchangesetです。
  """
  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [
      :attachable_type,
      :attachable_id,
      :filename,
      :content_type,
      :byte_size,
      :storage_key,
      :uploaded_by_user_id
    ])
    |> validate_required([
      :attachable_type,
      :attachable_id,
      :filename,
      :content_type,
      :byte_size,
      :storage_key,
      :uploaded_by_user_id
    ])
    |> validate_length(:filename, max: 255)
    |> validate_inclusion(:content_type, content_types())
    |> validate_number(:byte_size, greater_than: 0)
    |> assoc_constraint(:uploaded_by_user)
  end
end
