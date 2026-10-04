defmodule CoreAppWeb.Mcp.Tools.Masters do
  @moduledoc """
  荷主・車両・ドライバーのマスタを調べるMCPツールです。

  配車表の名称を、システムに登録されているマスタと突き合わせるために使います。
  配車に選べるもの（有効な荷主、廃車でない車両、退職していないドライバー）だけを返します。
  """

  alias CoreApp.Dispatches.Import
  alias CoreApp.Drivers
  alias CoreApp.Shippers
  alias CoreApp.Vehicles

  def tools do
    [
      %{
        name: "list_vehicles",
        description: "配車に使える車両（廃車を除く）の一覧を返します。ナンバー（plate_number）で配車表の車両と突き合わせます。",
        input_schema: schema("ナンバーの部分一致（表記ゆれ・空白は無視）"),
        run: fn args, %{scope: scope} ->
          {:ok, list(Vehicles.all_selectable_vehicles(scope), args, [:plate_number], &vehicle/1)}
        end
      },
      %{
        name: "list_drivers",
        description: "配車に使えるドライバー（退職者を除く）の一覧を返します。",
        input_schema: schema("氏名・コードの部分一致（表記ゆれ・空白は無視）"),
        run: fn args, %{scope: scope} ->
          {:ok, list(Drivers.all_selectable_drivers(scope), args, [:name, :code], &driver/1)}
        end
      },
      %{
        name: "list_shippers",
        description: "配車に使える荷主（有効のみ）の一覧を返します。",
        input_schema: schema("荷主名・コードの部分一致（表記ゆれ・空白は無視）"),
        run: fn args, %{scope: scope} ->
          {:ok, list(Shippers.all_selectable_shippers(scope), args, [:name, :code], &shipper/1)}
        end
      }
    ]
  end

  defp schema(query_description) do
    %{
      "type" => "object",
      "properties" => %{"q" => %{"type" => "string", "description" => query_description}}
    }
  end

  defp list(records, args, keys, present) do
    records = filter(records, args["q"], keys)

    %{"count" => length(records), "items" => Enum.map(records, present)}
  end

  defp filter(records, q, keys) do
    wanted = Import.normalize_name(q)

    if wanted == "" do
      records
    else
      Enum.filter(records, fn record ->
        Enum.any?(keys, &String.contains?(Import.normalize_name(Map.get(record, &1)), wanted))
      end)
    end
  end

  defp vehicle(vehicle) do
    %{
      "id" => vehicle.id,
      "plate_number" => vehicle.plate_number,
      "vehicle_class" => vehicle.vehicle_class,
      "maker" => vehicle.maker,
      "model_name" => vehicle.model_name,
      "capacity_kg" => vehicle.capacity_kg,
      "status" => vehicle.status,
      "office_id" => vehicle.office_id
    }
  end

  defp driver(driver) do
    %{
      "id" => driver.id,
      "code" => driver.code,
      "name" => driver.name,
      "employment_type" => driver.employment_type,
      "office_id" => driver.office_id
    }
  end

  defp shipper(shipper) do
    %{
      "id" => shipper.id,
      "code" => shipper.code,
      "name" => shipper.name,
      "office_id" => shipper.office_id
    }
  end
end
