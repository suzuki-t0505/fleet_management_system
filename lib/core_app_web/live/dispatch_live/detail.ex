defmodule CoreAppWeb.DispatchLive.Detail do
  @moduledoc "配車の詳細表示（管理者向けと一般利用者向けで共通）のコンポーネントです。"
  use CoreAppWeb, :html

  alias CoreApp.Dispatches.Dispatch

  alias CoreAppWeb.DispatchLive.Labels

  @doc """
  配車の基本情報・配送明細・料金内訳を表示します。
  """
  attr :dispatch, :map, required: true
  attr :show_amount, :boolean, default: true

  def sections(assigns) do
    ~H"""
    <.section_card title="基本情報">
      <.definition_list>
        <:item label="タイトル">{@dispatch.title}</:item>
        <:item label="荷主">{@dispatch.shipper.name}</:item>
        <:item label="配送開始">{format_datetime(@dispatch.started_at)}</:item>
        <:item label="配送終了">{format_datetime(@dispatch.ended_at)}</:item>
        <:item label="車両">
          {@dispatch.vehicle.plate_number}（{@dispatch.vehicle.model_name}）
        </:item>
        <:item label="ドライバー">{@dispatch.driver.name}</:item>
        <:item label="拠点">{@dispatch.office.name}</:item>
      </.definition_list>
    </.section_card>

    <.section_card title="説明">
      <p class="text-body-sm whitespace-pre-wrap text-ink-secondary">
        {@dispatch.description || "-"}
      </p>
    </.section_card>

    <.section_card title="配送先">
      <p :if={@dispatch.deliveries == []} class="text-body-sm text-ink-muted">
        配送先は登録されていません。
      </p>
      <.data_table
        :if={@dispatch.deliveries != []}
        id="dispatch-deliveries"
        rows={@dispatch.deliveries}
      >
        <:col :let={delivery} label="順">{delivery.position}</:col>
        <:col :let={delivery} label="配送先">{delivery.destination}</:col>
        <:col :let={delivery} label="荷積み">{format_datetime(delivery.loading_at)}</:col>
        <:col :let={delivery} label="荷降ろし">{format_datetime(delivery.unloading_at)}</:col>
        <:col
          :let={delivery}
          :if={@show_amount and @dispatch.pricing_type == :per_delivery}
          label="配送料金"
        >
          {Labels.yen(delivery.fare_yen)}
        </:col>
      </.data_table>
    </.section_card>

    <.section_card :if={@show_amount} title="料金">
      <.definition_list>
        <:item label="料金方式">{Labels.pricing_type(@dispatch.pricing_type)}</:item>
        <:item :if={@dispatch.pricing_type == :course_total} label="コース料金">
          {Labels.yen(@dispatch.course_fare_yen)}
        </:item>
        <:item :if={@dispatch.pricing_type == :per_delivery} label="配送料金の合計">
          {Labels.yen(Dispatch.fare_total_yen(@dispatch))}
        </:item>
        <:item label="高速料金">{Labels.yen(@dispatch.toll_yen)}</:item>
        <:item label="受取金額の合計">
          <span class="text-title text-ink" id="dispatch-total">
            {Labels.yen(Dispatch.total_amount_yen(@dispatch))}
          </span>
        </:item>
      </.definition_list>
    </.section_card>
    """
  end
end
