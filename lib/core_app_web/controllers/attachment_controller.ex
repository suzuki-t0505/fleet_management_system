defmodule CoreAppWeb.AttachmentController do
  @moduledoc """
  添付ファイルを配信するコントローラです。

  **対象レコードをスコープ付きで引き直してから**配信します。参照できない利用者には、
  他拠点に何が存在するかを推測させないため 404 を返します。

  認可を通ったあとは、保存先が発行する署名付きURL（5分間有効）へリダイレクトします。
  署名できない保存先（開発・テストのローカル保存）では、これまでどおりアプリが本体を配信します。
  """
  use CoreAppWeb, :controller

  alias CoreApp.Attachments
  alias CoreApp.Attachments.Attachment
  alias CoreApp.Incidents
  alias CoreApp.Maintenances
  alias CoreApp.Utils.Storage
  alias CoreApp.Vehicles

  def download(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    attachment = Attachments.get_attachment!(id)

    _attachable = fetch_attachable!(scope, attachment)

    case Storage.signed_url(attachment.storage_key) do
      {:ok, url} -> redirect(conn, external: url)
      {:error, _reason} -> send_attachment(conn, attachment)
    end
  end

  # 署名付きURLを発行できない保存先（ローカル）向けのフォールバック。
  defp send_attachment(conn, attachment) do
    {:ok, binary} = Attachments.read_attachment(attachment)

    conn
    |> put_resp_content_type(attachment.content_type)
    |> put_resp_header("content-disposition", content_disposition(attachment.filename))
    |> put_resp_header("cache-control", "private, no-store")
    |> send_resp(200, binary)
  end

  # 対象のContextにスコープ付きで問い合わせる。参照できない場合は Ecto.NoResultsError が上がる。
  defp fetch_attachable!(scope, %Attachment{attachable_type: :incident} = attachment) do
    Incidents.get_incident!(scope, attachment.attachable_id)
  end

  defp fetch_attachable!(scope, %Attachment{attachable_type: :maintenance} = attachment) do
    Maintenances.get_maintenance!(scope, attachment.attachable_id)
  end

  defp fetch_attachable!(scope, %Attachment{attachable_type: :vehicle} = attachment) do
    Vehicles.get_vehicle!(scope, attachment.attachable_id)
  end

  # 日本語のファイル名を扱うため RFC 5987 形式で指定する
  defp content_disposition(filename) do
    "inline; filename*=UTF-8''#{URI.encode(filename)}"
  end
end
