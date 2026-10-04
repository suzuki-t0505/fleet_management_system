defmodule CoreApp.Dispatches.Import do
  @moduledoc """
  表計算ソフトなどの配車表の1行分（荷主・車両・ドライバーを名称で指定したもの）を、
  配車の入力値（IDで指定したもの）に変換する純関数のモジュールです。

  マスタの検索や保存はしません。マスタは呼び出し側（`CoreApp.Dispatches`）が渡します。

  名称は完全一致で解決します。表記ゆれ（全角半角・空白の有無・大文字小文字）だけは吸収しますが、
  推測はしません。該当なし・複数該当はエラーにします（自動作成もしません）。
  """

  alias CoreApp.Vehicles.Vehicle

  @doc """
  名称の比較用に表記ゆれを吸収します。

  全角英数・半角カナなどを正規化（NFKC）し、空白（全角を含む）をすべて取り除き、小文字にします。
  """
  def normalize_name(nil), do: ""

  def normalize_name(value) when is_binary(value) do
    value
    |> :unicode.characters_to_nfkc_binary()
    |> to_binary(value)
    |> String.replace(~r/[\s\x{3000}]+/u, "")
    |> String.downcase()
  end

  def normalize_name(value) when is_integer(value), do: Integer.to_string(value)

  # Excelの数値セルは 123.0 で届くことがあるため、小数部が無ければ整数として扱う
  def normalize_name(value) when is_float(value) do
    if value == Float.round(value), do: value |> trunc() |> Integer.to_string(), else: ""
  end

  def normalize_name(_value), do: ""

  defp to_binary(converted, _original) when is_binary(converted), do: converted
  defp to_binary(_error, original), do: original

  @doc """
  1行分の入力を、配車の入力値に変換します。

  車両は `plate_number`、ドライバーと荷主は `code`、なければ `name` で探します。
  ドライバーと荷主は、車両の配置拠点のものに絞って探します（配車は車両の拠点に従うため）。

  成功したら `{:ok, attrs, refs}` を返します。`attrs` は `Dispatches.change_dispatch/3` に渡せる
  文字列キーのマップ、`refs` は解決した `%{vehicle:, driver:, shipper:}` です。
  失敗したら、すべての問題をまとめた `{:error, メッセージのリスト}` を返します。
  """
  def resolve(row, %{vehicles: vehicles, drivers: drivers, shippers: shippers}) do
    vehicle = find(vehicles, row["vehicle"], [:plate_number], "車両")
    office_id = with {:ok, v} <- vehicle, do: v.office_id

    driver = find(in_office(drivers, office_id), row["driver"], [:code, :name], "ドライバー")
    shipper = find(in_office(shippers, office_id), row["shipper"], [:code, :name], "荷主")

    case Enum.filter([vehicle, driver, shipper], &match?({:error, _message}, &1)) do
      [] ->
        {:ok, v} = vehicle
        {:ok, d} = driver
        {:ok, s} = shipper

        {:ok, build_attrs(row, s, v, d), %{vehicle: v, driver: d, shipper: s}}

      errors ->
        {:error, Enum.map(errors, fn {:error, message} -> message end)}
    end
  end

  defp in_office(records, office_id) when is_binary(office_id) do
    Enum.filter(records, &(&1.office_id == office_id))
  end

  defp in_office(records, _office_id), do: records

  defp find(candidates, query, keys, label) do
    wanted = normalize_name(query)

    if wanted == "" do
      {:error, "#{label}が未入力です"}
    else
      keys
      |> Enum.find_value(:none, &match_by(candidates, &1, wanted))
      |> found(query, label)
    end
  end

  defp match_by(candidates, key, wanted) do
    case Enum.filter(candidates, &(normalize_name(Map.get(&1, key)) == wanted)) do
      [] -> nil
      [one] -> {:ok, one}
      many -> {:ambiguous, many}
    end
  end

  defp found({:ok, _record} = ok, _query, _label), do: ok

  defp found({:ambiguous, records}, query, label) do
    names = Enum.map_join(records, "、", &display_name/1)
    {:error, "#{label}「#{query}」に該当する候補が複数あります（#{names}）"}
  end

  defp found(:none, query, label) do
    {:error, "#{label}「#{query}」は登録されていません（無効・廃車・退職済み、または対象外の拠点を含みます）"}
  end

  defp display_name(%Vehicle{plate_number: plate_number}), do: plate_number
  defp display_name(%{code: nil, name: name}), do: name
  defp display_name(%{code: code, name: name}), do: "#{name}（#{code}）"

  defp build_attrs(row, shipper, vehicle, driver) do
    %{
      "shipper_id" => shipper.id,
      "vehicle_id" => vehicle.id,
      "driver_id" => driver.id,
      "title" => row["title"],
      "description" => row["description"],
      "started_at" => datetime(row["started_at"]),
      "ended_at" => datetime(row["ended_at"]),
      "pricing_type" => pricing_type(row),
      "course_fare_yen" => row["course_fare_yen"],
      "toll_yen" => row["toll_yen"],
      "deliveries" => deliveries(row["deliveries"])
    }
  end

  # 料金方式が無い場合、コース料金が無く配送ごとの料金があれば「配送ごと」とみなす
  defp pricing_type(%{"pricing_type" => type}) when type not in [nil, ""], do: type

  defp pricing_type(row) do
    if blank?(row["course_fare_yen"]) and
         Enum.any?(delivery_list(row), &(!blank?(&1["fare_yen"]))) do
      "per_delivery"
    else
      "course_total"
    end
  end

  defp delivery_list(%{"deliveries" => list}) when is_list(list), do: Enum.filter(list, &is_map/1)
  defp delivery_list(_row), do: []

  defp blank?(value), do: value in [nil, ""]

  # フォームと同じ形（連番文字列キーのマップ）にする
  defp deliveries(list) when is_list(list) do
    list
    |> Enum.filter(&is_map/1)
    |> Enum.with_index()
    |> Map.new(fn {delivery, index} ->
      {Integer.to_string(index),
       %{
         "destination" => delivery["destination"],
         "fare_yen" => delivery["fare_yen"],
         "loading_at" => datetime(delivery["loading_at"]),
         "unloading_at" => datetime(delivery["unloading_at"])
       }}
    end)
  end

  defp deliveries(_other), do: %{}

  # 「2026-10-04 09:00」のように区切りがスペースの値を ISO 形式にそろえる。
  # タイムゾーンが無い値はJSTとして扱われる（`ConvertDatetime.parse_input/1`）。
  defp datetime(value) when is_binary(value) do
    value |> String.trim() |> String.replace(~r/^(\d{4}-\d{2}-\d{2}) (?=\d)/, "\\1T")
  end

  defp datetime(value), do: value

  @doc """
  changesetのエラーを、行の結果に載せる文字列のリストにします。

  配送明細のエラーは `配送明細1.配送先: ...` の形にします。
  """
  def format_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&interpolate/1)
    |> flatten_errors([])
  end

  defp interpolate({message, opts}) do
    Regex.replace(~r"%{(\w+)}", message, fn _match, key ->
      opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
    end)
  end

  defp flatten_errors(errors, path) when is_map(errors) do
    Enum.flat_map(errors, fn {field, value} -> flatten_errors(value, path ++ [field]) end)
  end

  # has_many の子のエラーは、子ごとのマップのリストで返る
  defp flatten_errors([first | _rest] = list, path) when is_map(first) do
    list
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {errors, number} -> flatten_errors(errors, nested(path, number)) end)
  end

  defp flatten_errors(messages, path) when is_list(messages) do
    Enum.map(messages, &"#{label(path)}#{&1}")
  end

  defp nested(path, number) do
    List.update_at(path, -1, fn field -> "#{field}#{number}" end)
  end

  @labels %{
    "title" => "配送タイトル",
    "started_at" => "配送開始日時",
    "ended_at" => "配送終了日時",
    "pricing_type" => "料金方式",
    "course_fare_yen" => "コース料金",
    "toll_yen" => "高速料金",
    "shipper_id" => "荷主",
    "vehicle_id" => "車両",
    "driver_id" => "ドライバー",
    "deliveries" => "配送明細",
    "destination" => "配送先",
    "fare_yen" => "配送料金",
    "loading_at" => "荷積み日時",
    "unloading_at" => "荷降ろし日時"
  }

  defp label(path) do
    Enum.map_join(path, ".", &field_label/1) <> " "
  end

  # 「deliveries1」のように連番が付いた配送明細はラベルに連番を残す
  defp field_label(field) do
    name = to_string(field)

    case Regex.run(~r/^(deliveries)(\d+)$/, name) do
      [_all, base, number] -> "#{Map.fetch!(@labels, base)}#{number}"
      nil -> Map.get(@labels, name, name)
    end
  end
end
