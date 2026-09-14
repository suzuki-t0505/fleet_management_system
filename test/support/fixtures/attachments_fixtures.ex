defmodule CoreApp.AttachmentsFixtures do
  @moduledoc """
  添付ファイルのテストデータを生成します。

  実体は一時ディレクトリに書き出し、保存先はテスト用のローカルアダプタを使います。
  """

  alias CoreApp.Accounts.Scope
  alias CoreApp.Attachments

  @png_header <<137, 80, 78, 71, 13, 10, 26, 10>>
  @jpeg_header <<255, 216, 255>>
  @pdf_header "%PDF-1.7"

  @doc """
  PNGとして正しい先頭バイトを持つ一時ファイルを作り、パスを返します。
  """
  def png_path(content \\ "dummy image"), do: temp_file("png", @png_header <> content)

  @doc """
  JPEGとして正しい先頭バイトを持つ一時ファイルを作ります。
  """
  def jpeg_path(content \\ "dummy image"), do: temp_file("jpg", @jpeg_header <> content)

  @doc """
  PDFとして正しい先頭バイトを持つ一時ファイルを作ります。
  """
  def pdf_path(content \\ "dummy document"), do: temp_file("pdf", @pdf_header <> content)

  @doc """
  拡張子だけを偽装した（先頭バイトが一致しない）一時ファイルを作ります。
  """
  def disguised_path, do: temp_file("png", "これは画像ではありません")

  @doc """
  添付ファイルを作成します。
  """
  def attachment_fixture(%Scope{} = scope, attachable, attrs \\ %{}) do
    path = Map.get(attrs, :path) || png_path()

    {:ok, attachment} =
      Attachments.create_attachment(scope, attachable, %{
        path: path,
        filename: Map.get(attrs, :filename, "現場写真.png"),
        byte_size: File.stat!(path).size
      })

    attachment
  end

  defp temp_file(extension, content) do
    path =
      Path.join(
        System.tmp_dir!(),
        "attachment-#{System.unique_integer([:positive])}.#{extension}"
      )

    File.write!(path, content)

    path
  end
end
