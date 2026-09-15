defmodule CoreApp.Utils.Storage.LocalTest do
  use ExUnit.Case, async: true

  alias CoreApp.Utils.Storage
  alias CoreApp.Utils.Storage.Local

  setup do
    source = Path.join(System.tmp_dir!(), "storage-#{System.unique_integer([:positive])}.png")
    File.write!(source, "画像の中身")

    on_exit(fn -> File.rm(source) end)

    %{source: source, key: "attachments/incident/#{Ecto.ULID.generate()}/photo.png"}
  end

  test "テスト環境ではローカルアダプタを使う" do
    assert Storage.adapter() == Local
  end

  test "保存・読み出し・削除ができる", %{source: source, key: key} do
    assert :ok = Storage.put(key, source, "image/png")
    assert {:ok, "画像の中身"} = Storage.read(key)

    assert :ok = Storage.delete(key)
    assert {:error, :enoent} = Storage.read(key)
  end

  test "存在しないファイルの削除は成功として扱う" do
    assert :ok = Storage.delete("attachments/incident/#{Ecto.ULID.generate()}/none.png")
  end

  test "署名付きURLは発行できない", %{key: key} do
    assert {:error, :not_supported} = Storage.signed_url(key)
  end

  test "保存先はルート配下に作られる", %{source: source, key: key} do
    :ok = Storage.put(key, source, "image/png")

    assert File.exists?(Path.join(Local.root(), key))

    File.rm(Path.join(Local.root(), key))
  end
end
