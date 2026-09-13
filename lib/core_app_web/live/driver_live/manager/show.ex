defmodule CoreAppWeb.DriverLive.Manager.Show do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Drivers
  alias CoreApp.Utils.ConvertDatetime

  alias CoreAppWeb.DriverLive.Labels

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    driver = Drivers.get_driver!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(driver: driver)
     |> assign(page_title: driver.name)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          navigate={~p"/management/drivers/#{@driver}/edit"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          編集
        </.link>
      </:actions>

      <div class="space-y-6">
        <.link
          navigate={~p"/management/drivers"}
          class="text-body-sm inline-flex items-center gap-1 text-ink-muted hover:text-primary"
        >
          <.icon name="hero-arrow-left" class="size-4" /> 運転者一覧へ戻る
        </.link>

        <.section_card title="基本情報">
          <.definition_list>
            <:item label="運転者コード">{@driver.code}</:item>
            <:item label="氏名">{@driver.name}</:item>
            <:item label="氏名かな">{@driver.name_kana}</:item>
            <:item label="拠点">{@driver.office.name}</:item>
            <:item label="雇用区分">{Labels.employment_type(@driver.employment_type)}</:item>
            <:item label="入社年月日">{format_date(@driver.hired_on)}</:item>
            <:item label="退職年月日">{format_date(@driver.retired_on)}</:item>
          </.definition_list>
        </.section_card>

        <.section_card title="免許情報">
          <p
            :if={license_warning(@driver)}
            class={[
              "text-body-sm mb-4 rounded-md px-4 py-3 text-on-primary",
              license_warning_color(@driver)
            ]}
          >
            {license_warning(@driver)}
          </p>
          <.definition_list>
            <:item label="免許証番号">{@driver.license_number}</:item>
            <:item label="免許種類">{Labels.license_types(@driver.license_types)}</:item>
            <:item label="免許証有効期限">
              <.deadline_badge date={@driver.license_expires_on} />
            </:item>
          </.definition_list>
        </.section_card>

        <.section_card title="アカウント">
          <.definition_list :if={@driver.user}>
            <:item label="氏名">{@driver.user.name}</:item>
            <:item label="メールアドレス">{@driver.user.email}</:item>
            <:item label="ロール">{role_label(@driver.user.role)}</:item>
            <:item label="状態">{if @driver.user.active, do: "有効", else: "無効"}</:item>
          </.definition_list>
          <p :if={is_nil(@driver.user)} class="text-body-sm text-ink-muted">
            アカウントは紐付いていません。紐付けると、この運転者本人が日報を入力できるようになります。
          </p>
        </.section_card>

        <.section_card title="備考">
          <p class="text-body-sm whitespace-pre-wrap text-ink-secondary">{@driver.note || "-"}</p>
        </.section_card>

        <.section_card title="履歴">
          <.placeholder message="運行日報・事故/ヒヤリ記録は、各機能の実装後にここへ表示されます。" />
        </.section_card>
      </div>
    </Layouts.app>
    """
  end

  defp license_warning(driver) do
    case ConvertDatetime.days_until(driver.license_expires_on) do
      nil -> nil
      days when days < 0 -> "免許証の有効期限が#{abs(days)}日超過しています。運転業務に就かせる前に確認してください。"
      days when days <= 30 -> "免許証の有効期限まであと#{days}日です。更新手続きを確認してください。"
      _days -> nil
    end
  end

  defp license_warning_color(driver) do
    if ConvertDatetime.days_until(driver.license_expires_on) < 0 do
      "bg-accent-orange-deep"
    else
      "bg-accent-orange"
    end
  end

  defp role_label(:admin), do: "管理者"
  defp role_label(:manager), do: "運行管理者"
  defp role_label(:member), do: "一般利用者"
end
