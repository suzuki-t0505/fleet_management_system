defmodule CoreApp.Utils.Storage.Local do
  @moduledoc """
  添付ファイルをローカルディスクに保存するアダプタです。開発・テストで使います。

  保存先のルートは `config :core_app, :storage, root: "..."` で指定します。
  """
  @behaviour CoreApp.Utils.Storage

  alias CoreApp.Utils.Storage

  @default_root "priv/uploads"

  @impl CoreApp.Utils.Storage
  def put(key, source_path, _content_type) do
    path = path_for(key)

    with :ok <- path |> Path.dirname() |> File.mkdir_p(),
         {:ok, _bytes} <- File.copy(source_path, path) do
      :ok
    end
  end

  @impl CoreApp.Utils.Storage
  def read(key) do
    File.read(path_for(key))
  end

  @impl CoreApp.Utils.Storage
  def delete(key) do
    case File.rm(path_for(key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl CoreApp.Utils.Storage
  def signed_url(_key), do: {:error, :not_supported}

  @doc """
  保存先のルートディレクトリを返します。
  """
  def root, do: Storage.config(:root, @default_root)

  defp path_for(key), do: Path.join(root(), key)
end
