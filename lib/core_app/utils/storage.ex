defmodule CoreApp.Utils.Storage do
  @moduledoc """
  添付ファイルの保存先を抽象化するモジュールです。

  開発・テストはローカルディスク（`Storage.Local`）、本番は Cloud Storage
  （`Storage.Gcs`）を使います。保存先の差し替えがこのモジュールの設定だけで済むよう、
  呼び出し側はアダプタを直接参照しません。

  ダウンロードは常にアプリケーションを経由します（公開URL・署名付きURLは発行しません）。
  参照できるかどうかの判定を1か所に集めるためです。
  """

  @doc """
  ローカルのファイルを保存先へ書き込みます。
  """
  @callback put(key :: String.t(), source_path :: String.t(), content_type :: String.t()) ::
              :ok | {:error, term()}

  @doc """
  保存したファイルの内容を読み出します。
  """
  @callback read(key :: String.t()) :: {:ok, binary()} | {:error, term()}

  @doc """
  保存したファイルを削除します。
  """
  @callback delete(key :: String.t()) :: :ok | {:error, term()}

  @doc """
  ファイルを保存します。
  """
  def put(key, source_path, content_type), do: adapter().put(key, source_path, content_type)

  @doc """
  ファイルを読み出します。
  """
  def read(key), do: adapter().read(key)

  @doc """
  ファイルを削除します。
  """
  def delete(key), do: adapter().delete(key)

  @doc """
  設定されているアダプタを返します。

  設定はモジュール属性ではなく関数で解決します（coding-rules 13.3）。
  """
  def adapter do
    :core_app
    |> Application.get_env(:storage, [])
    |> Keyword.get(:adapter, CoreApp.Utils.Storage.Local)
  end

  @doc """
  アダプタごとの設定値を返します。
  """
  def config(key, default \\ nil) do
    :core_app
    |> Application.get_env(:storage, [])
    |> Keyword.get(key, default)
  end
end
