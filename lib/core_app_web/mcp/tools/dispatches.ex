defmodule CoreAppWeb.Mcp.Tools.Dispatches do
  @moduledoc """
  配車を検証・登録・参照するMCPツールです。

  表計算ソフトの配車表の読み取りと列の対応づけは、MCPクライアント（Claude）が行います。
  このツールは、対応づけ済みの行を受け取って検証・登録します。
  """

  alias CoreApp.Dispatches
  alias CoreApp.Utils.ConvertDatetime

  @row_schema %{
    "type" => "object",
    "description" => "配車表の1行。荷主・車両・ドライバーは名称で指定します（マスタに無い場合はエラー。自動作成しません）。",
    "properties" => %{
      "ref" => %{"type" => "string", "description" => "結果に付けて返す識別子（例: Excelの行番号 \"12\"）"},
      "title" => %{"type" => "string", "description" => "配送タイトル（必須）"},
      "shipper" => %{"type" => "string", "description" => "荷主のコードまたは名称（必須）"},
      "vehicle" => %{"type" => "string", "description" => "車両のナンバー（plate_number）（必須）"},
      "driver" => %{"type" => "string", "description" => "ドライバーのコードまたは氏名（必須）"},
      "started_at" => %{
        "type" => "string",
        "description" => "配送開始日時。JST、例 2026-10-04T09:00（必須）"
      },
      "ended_at" => %{
        "type" => "string",
        "description" => "配送終了日時。JST、開始より後（必須）"
      },
      "pricing_type" => %{
        "type" => "string",
        "enum" => ["course_total", "per_delivery"],
        "description" =>
          "料金方式。course_total=コース一括、per_delivery=配送ごと。省略時は、コース料金が無く配送料金があれば per_delivery、それ以外は course_total"
      },
      "course_fare_yen" => %{
        "type" => "integer",
        "description" => "コース料金（円）。course_total のとき必須"
      },
      "toll_yen" => %{"type" => "integer", "description" => "高速料金（円）。省略時は0"},
      "description" => %{"type" => "string", "description" => "配送の説明"},
      "deliveries" => %{
        "type" => "array",
        "description" => "配送明細（配送先ごと）。per_delivery のときは1件以上必須",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "destination" => %{"type" => "string", "description" => "配送先（必須）"},
            "fare_yen" => %{
              "type" => "integer",
              "description" => "配送料金（円）。per_delivery のとき必須"
            },
            "loading_at" => %{"type" => "string", "description" => "荷積み日時（JST、任意）"},
            "unloading_at" => %{"type" => "string", "description" => "荷降ろし日時（JST、任意）"}
          },
          "required" => ["destination"]
        }
      }
    },
    "required" => ["title", "shipper", "vehicle", "driver", "started_at", "ended_at"]
  }

  def tools do
    [
      %{
        name: "validate_dispatches",
        description:
          "配車表の行を検証します。保存はしません。荷主・車両・ドライバーの名称解決、入力検証、" <>
            "時間帯の重なり（警告）、二重登録を行ごとに返します。create_dispatches の前に必ず実行してください。",
        input_schema: rows_schema(),
        run: fn args, %{scope: scope} -> validate(scope, args) end
      },
      %{
        name: "create_dispatches",
        description:
          "配車表の行を配車として登録します。全行が有効な場合のみ、まとめて登録します" <>
            "（1行でもエラーがあれば何も登録しません）。登録内容は監査ログに記録されます。" <>
            "ユーザーが検証結果（警告を含む）を確認してから実行してください。",
        input_schema: rows_schema(),
        run: fn args, context -> create(context, args) end
      },
      %{
        name: "list_dispatches",
        description: "登録済みの配車を配送開始日時の降順で返します。登録結果の確認や重複の確認に使います。",
        input_schema: %{
          "type" => "object",
          "properties" => %{
            "from" => %{"type" => "string", "description" => "配送開始日（JST）の期間の開始。例 2026-10-01"},
            "to" => %{"type" => "string", "description" => "配送開始日（JST）の期間の終了。例 2026-10-31"},
            "q" => %{"type" => "string", "description" => "タイトル・荷主名・配送先の検索ワード"},
            "shipper_id" => %{"type" => "string"},
            "vehicle_id" => %{"type" => "string"},
            "driver_id" => %{"type" => "string"},
            "page" => %{"type" => "integer"},
            "page_size" => %{"type" => "integer", "description" => "既定50、上限100"}
          }
        },
        run: fn args, %{scope: scope} -> {:ok, list(scope, args)} end
      }
    ]
  end

  defp rows_schema do
    %{
      "type" => "object",
      "properties" => %{
        "rows" => %{
          "type" => "array",
          "description" => "配車表の行。1回あたり最大#{Dispatches.max_import_rows()}行",
          "items" => @row_schema
        }
      },
      "required" => ["rows"]
    }
  end

  defp validate(scope, %{"rows" => rows}) when is_list(rows) do
    case Dispatches.validate_import(scope, rows) do
      {:ok, results} -> {:ok, report(results, %{"valid" => all_valid?(results)})}
      {:error, reason} -> {:error, import_error(reason)}
    end
  end

  defp validate(_scope, _args), do: {:error, "rows を配列で指定してください"}

  defp create(%{scope: scope, ip_address: ip_address}, %{"rows" => rows}) when is_list(rows) do
    case Dispatches.import_dispatches(scope, rows, ip_address: ip_address) do
      {:ok, results} ->
        {:ok, report(results, %{"created" => true, "created_count" => length(results)})}

      {:error, {:invalid, results}} ->
        {:ok,
         report(results, %{
           "created" => false,
           "message" => "エラーのある行があるため、何も登録していません。rows を修正して再実行してください。"
         })}

      {:error, reason} ->
        {:error, import_error(reason)}
    end
  end

  defp create(_context, _args), do: {:error, "rows を配列で指定してください"}

  defp import_error(:unauthorized), do: "配車を登録・検証できるのは運行管理者以上です"
  defp import_error(:empty), do: "rows が空です"

  defp import_error(:too_many_rows),
    do: "一度に扱えるのは最大#{Dispatches.max_import_rows()}行です。分割してください"

  defp all_valid?(results), do: Enum.all?(results, &(&1.errors == []))

  defp report(results, extra) do
    Map.merge(extra, %{
      "error_count" => Enum.count(results, &(&1.errors != [])),
      "warning_count" => Enum.count(results, &(&1.warnings != [])),
      "rows" => Enum.map(results, &present_row/1)
    })
  end

  defp present_row(result) do
    %{
      "row" => result.index,
      "ref" => result.ref,
      "status" => if(result.errors == [], do: "ok", else: "error"),
      "errors" => result.errors,
      "warnings" => result.warnings,
      "summary" => summary(result),
      "dispatch_id" => result.dispatch && result.dispatch.id
    }
  end

  defp summary(%{refs: nil}), do: nil

  defp summary(%{refs: refs, attrs: attrs, total_amount_yen: total}) do
    %{
      "title" => attrs["title"],
      "shipper" => refs.shipper.name,
      "vehicle" => refs.vehicle.plate_number,
      "driver" => refs.driver.name,
      "started_at" => attrs["started_at"],
      "ended_at" => attrs["ended_at"],
      "deliveries" => map_size(attrs["deliveries"]),
      "total_amount_yen" => total
    }
  end

  defp list(scope, args) do
    params = Map.take(args, ~w(from to q shipper_id vehicle_id driver_id page page_size))
    page = Dispatches.list_dispatches(scope, params)

    %{
      "total_entries" => page.total_entries,
      "page" => page.page_number,
      "total_pages" => page.total_pages,
      "items" => Enum.map(page.entries, &present_dispatch/1)
    }
  end

  defp present_dispatch(dispatch) do
    %{
      "id" => dispatch.id,
      "title" => dispatch.title,
      "shipper" => dispatch.shipper.name,
      "vehicle" => dispatch.vehicle.plate_number,
      "driver" => dispatch.driver.name,
      "started_at" => ConvertDatetime.to_input_value(dispatch.started_at),
      "ended_at" => ConvertDatetime.to_input_value(dispatch.ended_at),
      "pricing_type" => dispatch.pricing_type,
      "total_amount_yen" => Dispatches.total_amount_yen(dispatch),
      "destinations" => Enum.map(dispatch.deliveries, & &1.destination)
    }
  end
end
