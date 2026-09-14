defmodule CoreAppWeb.AttachmentComponents do
  @moduledoc "添付ファイルのアップロード欄と一覧のコンポーネント"
  use Phoenix.Component
  use CoreAppWeb, :verified_routes

  import CoreAppWeb.CoreComponents, only: [icon: 1]

  alias CoreApp.Attachments.Attachment

  @doc """
  添付ファイルのアップロード欄です。

  `live_file_input` を使うため、`phx-change` を持つフォームの中に置いてください。
  """
  attr :upload, Phoenix.LiveView.UploadConfig, required: true
  attr :remaining, :integer, required: true, doc: "あと何件添付できるか"

  def upload_area(assigns) do
    ~H"""
    <div class="space-y-3">
      <label class="text-body-sm flex cursor-pointer items-center gap-2 rounded-md border border-dashed border-hairline bg-canvas-soft px-4 py-6 text-ink-muted hover:border-primary">
        <.icon name="hero-paper-clip" class="size-5" />
        <span>ファイルを選択（PDF・JPEG・PNG、1ファイル10MBまで）</span>
        <.live_file_input upload={@upload} class="sr-only" />
      </label>

      <p class="text-caption text-ink-muted">あと {@remaining} 件まで添付できます。</p>

      <div :for={entry <- @upload.entries} class="rounded-md border border-hairline bg-surface p-3">
        <div class="flex items-center justify-between gap-3">
          <span class="text-body-sm truncate text-ink-secondary">{entry.client_name}</span>
          <button
            type="button"
            phx-click="cancel_upload"
            phx-value-ref={entry.ref}
            class="text-caption text-ink-muted hover:text-accent-orange-deep"
          >
            取り消す
          </button>
        </div>
        <div class="mt-2 h-1 rounded-full bg-canvas-soft">
          <div class="h-1 rounded-full bg-primary" style={"width: #{entry.progress}%"}></div>
        </div>
        <p
          :for={error <- upload_errors(@upload, entry)}
          class="text-caption mt-1 text-accent-orange-deep"
        >
          {error_message(error)}
        </p>
      </div>

      <p :for={error <- upload_errors(@upload)} class="text-caption text-accent-orange-deep">
        {error_message(error)}
      </p>
    </div>
    """
  end

  @doc """
  添付ファイルの一覧です。`deletable` が真のとき削除ボタンを表示します。
  """
  attr :attachments, :list, required: true
  attr :deletable, :boolean, default: false

  def attachment_list(assigns) do
    ~H"""
    <p :if={@attachments == []} class="text-body-sm text-ink-muted">添付ファイルはありません。</p>

    <ul :if={@attachments != []} class="space-y-2">
      <li
        :for={attachment <- @attachments}
        id={"attachment-#{attachment.id}"}
        class="flex items-center gap-3 rounded-md border border-hairline bg-surface px-3 py-2"
      >
        <.icon name="hero-document" class="size-4 shrink-0 text-ink-faint" />
        <.link
          href={~p"/attachments/#{attachment}"}
          target="_blank"
          class="text-body-sm min-w-0 flex-1 truncate text-primary hover:underline"
        >
          {attachment.filename}
        </.link>
        <span class="text-caption shrink-0 text-ink-muted">{format_size(attachment.byte_size)}</span>
        <button
          :if={@deletable}
          type="button"
          phx-click="delete_attachment"
          phx-value-id={attachment.id}
          data-confirm="この添付ファイルを削除しますか？"
          class="text-caption shrink-0 text-ink-muted hover:text-accent-orange-deep"
        >
          削除
        </button>
      </li>
    </ul>
    """
  end

  @doc """
  アップロードで受け入れる拡張子の一覧を返します。
  """
  def accepted_extensions, do: Attachment.extensions()

  defp error_message(:too_large), do: "ファイルサイズが上限（10MB）を超えています"
  defp error_message(:not_accepted), do: "PDF・JPEG・PNG のみ添付できます"
  defp error_message(:too_many_files), do: "添付できる件数の上限を超えています"
  defp error_message(_error), do: "アップロードできませんでした"

  defp format_size(byte_size) when byte_size < 1024, do: "#{byte_size} B"

  defp format_size(byte_size) when byte_size < 1024 * 1024 do
    "#{Float.round(byte_size / 1024, 1)} KB"
  end

  defp format_size(byte_size), do: "#{Float.round(byte_size / (1024 * 1024), 1)} MB"
end
