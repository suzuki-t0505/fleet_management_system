# 開発環境用の初期データ。
#
#     docker compose run --rm web mix run priv/repo/seeds.exs
#
# 再実行してもエラーにならないよう、既存レコードがある場合は作成をスキップする。
# ここで設定するパスワードは開発環境専用。本番環境では絶対に使用しない。

alias CoreApp.Accounts
alias CoreApp.Accounts.Scope
alias CoreApp.Incidents
alias CoreApp.Offices
alias CoreApp.Drivers
alias CoreApp.OperationReports
alias CoreApp.Vehicles
alias CoreApp.Utils.ConvertDatetime

password = "password1234567"

offices = [
  %{
    "code" => "HQ",
    "name" => "本社",
    "postal_code" => "100-0005",
    "address" => "東京都千代田区丸の内1-1-1",
    "phone" => "03-1000-0000"
  },
  %{
    "code" => "TKY",
    "name" => "東京営業所",
    "postal_code" => "135-0064",
    "address" => "東京都江東区青海2-4-24",
    "phone" => "03-2000-0000"
  }
]

offices =
  Map.new(offices, fn attrs ->
    office =
      case Offices.get_office_by_code(attrs["code"]) do
        nil ->
          {:ok, office} = Offices.create_office(attrs)
          office

        office ->
          office
      end

    {attrs["code"], office}
  end)

users = [
  %{email: "admin@example.com", name: "管理 太郎", role: :admin, office: "HQ"},
  %{email: "manager@example.com", name: "運行 花子", role: :manager, office: "TKY"},
  %{email: "driver@example.com", name: "運転 次郎", role: :member, office: "TKY"}
]

for attrs <- users do
  case Accounts.get_user_by_email(attrs.email) do
    nil ->
      {:ok, user} =
        Accounts.create_user(%{
          email: attrs.email,
          name: attrs.name,
          role: attrs.role,
          office_id: offices[attrs.office].id,
          password: password
        })

      IO.puts("created user: #{user.email} (#{user.role})")

    user ->
      IO.puts("skipped user: #{user.email}")
  end
end

# --- 車両 ---
# 期限が近いもの・超過したものを含め、一覧の表示を確認できるようにする。
today = ConvertDatetime.today()
admin_scope = Accounts.get_user_by_email("admin@example.com") |> Scope.for_user()

vehicles = [
  %{
    "plate_number" => "品川100あ1001",
    "vin" => "ELF-0001",
    "vehicle_class" => "medium",
    "maker" => "いすゞ",
    "model_name" => "エルフ",
    "first_registered_on" => "2021-04-12",
    "status" => "active",
    "capacity_kg" => "3000",
    "gross_weight_kg" => "7500",
    "seating_capacity" => "3",
    "fuel_type" => "diesel",
    "ownership" => "owned",
    "inspection_expires_on" => Date.add(today, 210),
    "liability_insurance_expires_on" => Date.add(today, 240),
    "voluntary_insurance_expires_on" => Date.add(today, 120),
    "next_periodic_3m_on" => Date.add(today, 45),
    "office" => "HQ"
  },
  %{
    "plate_number" => "品川100あ1002",
    "vin" => "CANTER-0002",
    "vehicle_class" => "medium",
    "maker" => "三菱ふそう",
    "model_name" => "キャンター",
    "first_registered_on" => "2019-08-03",
    "status" => "maintenance",
    "capacity_kg" => "2000",
    "fuel_type" => "diesel",
    "ownership" => "lease",
    "lease_expires_on" => Date.add(today, 400),
    "inspection_expires_on" => Date.add(today, 25),
    "liability_insurance_expires_on" => Date.add(today, 25),
    "next_periodic_3m_on" => Date.add(today, 5),
    "office" => "TKY"
  },
  %{
    "plate_number" => "練馬800か2001",
    "vin" => "GIGA-0003",
    "vehicle_class" => "large",
    "maker" => "いすゞ",
    "model_name" => "ギガ",
    "first_registered_on" => "2018-02-20",
    "status" => "active",
    "capacity_kg" => "13000",
    "gross_weight_kg" => "25000",
    "fuel_type" => "diesel",
    "ownership" => "owned",
    "inspection_expires_on" => Date.add(today, -12),
    "liability_insurance_expires_on" => Date.add(today, 60),
    "office" => "TKY"
  },
  %{
    "plate_number" => "品川480す3001",
    "vin" => "HIJET-0004",
    "vehicle_class" => "light",
    "maker" => "ダイハツ",
    "model_name" => "ハイゼット",
    "first_registered_on" => "2022-11-01",
    "status" => "idle",
    "capacity_kg" => "350",
    "seating_capacity" => "2",
    "fuel_type" => "gasoline",
    "ownership" => "owned",
    "inspection_expires_on" => Date.add(today, 500),
    "liability_insurance_expires_on" => Date.add(today, 500),
    "office" => "TKY"
  },
  %{
    "plate_number" => "品川100あ1003",
    "vin" => "FORWARD-0005",
    "vehicle_class" => "medium",
    "maker" => "いすゞ",
    "model_name" => "フォワード",
    "first_registered_on" => "2017-06-15",
    "status" => "scrapped",
    "fuel_type" => "diesel",
    "ownership" => "owned",
    "inspection_expires_on" => Date.add(today, -300),
    "liability_insurance_expires_on" => Date.add(today, -300),
    "office" => "HQ"
  }
]

for attrs <- vehicles do
  {office_code, attrs} = Map.pop(attrs, "office")

  if Vehicles.list_vehicles(admin_scope, %{"q" => attrs["plate_number"], "status" => "all"}).total_entries ==
       0 do
    {:ok, vehicle} =
      Vehicles.create_vehicle(admin_scope, Map.put(attrs, "office_id", offices[office_code].id))

    IO.puts("created vehicle: #{vehicle.plate_number}")
  else
    IO.puts("skipped vehicle: #{attrs["plate_number"]}")
  end
end

# --- 運転者 ---
# driver@example.com のアカウントを1名に紐付け、日報の入力者と運転者の対応を確認できるようにする。
driver_user = Accounts.get_user_by_email("driver@example.com")

drivers = [
  %{
    "code" => "DR-001",
    "name" => "運転 次郎",
    "name_kana" => "うんてん じろう",
    "employment_type" => "full_time",
    "hired_on" => "2019-04-01",
    "license_number" => "302011112222",
    "license_types" => ["large", "medium", "ordinary"],
    "license_expires_on" => Date.add(today, 420),
    "user_id" => driver_user.id,
    "office" => "TKY"
  },
  %{
    "code" => "DR-002",
    "name" => "配送 花子",
    "name_kana" => "はいそう はなこ",
    "employment_type" => "contract",
    "hired_on" => "2023-07-16",
    "license_number" => "302033334444",
    "license_types" => ["medium", "ordinary"],
    "license_expires_on" => Date.add(today, 20),
    "office" => "TKY"
  },
  %{
    "code" => "DR-003",
    "name" => "長距離 三郎",
    "name_kana" => "ちょうきょり さぶろう",
    "employment_type" => "full_time",
    "hired_on" => "2015-10-01",
    "license_number" => "302055556666",
    "license_types" => ["large", "towing"],
    "license_expires_on" => Date.add(today, -8),
    "office" => "HQ"
  },
  %{
    "code" => "DR-004",
    "name" => "退職 四郎",
    "name_kana" => "たいしょく しろう",
    "employment_type" => "retired",
    "hired_on" => "2012-04-01",
    "retired_on" => Date.add(today, -60),
    "license_number" => "302077778888",
    "license_types" => ["medium"],
    "license_expires_on" => Date.add(today, 300),
    "office" => "HQ"
  }
]

for attrs <- drivers do
  {office_code, attrs} = Map.pop(attrs, "office")

  if Drivers.list_drivers(admin_scope, %{"q" => attrs["code"], "employment_type" => "all"}).total_entries ==
       0 do
    {:ok, driver} =
      Drivers.create_driver(admin_scope, Map.put(attrs, "office_id", offices[office_code].id))

    IO.puts("created driver: #{driver.code} #{driver.name}")
  else
    IO.puts("skipped driver: #{attrs["code"]}")
  end
end

# --- 運行日報 ---
# 下書き・提出済み・承認済み・差戻しの4状態をそろえ、画面の確認に使えるようにする。
tky_vehicle = Vehicles.list_vehicles(admin_scope, %{"q" => "品川100あ1002"}).entries |> List.first()
tky_driver = Drivers.list_drivers(admin_scope, %{"q" => "DR-001"}).entries |> List.first()

report_seeds = [
  %{
    "days_ago" => 0,
    "start" => 52_000,
    "distance" => 120,
    "status" => "draft",
    "destination" => "東京都港区"
  },
  %{
    "days_ago" => 1,
    "start" => 52_120,
    "distance" => 180,
    "status" => "submitted",
    "destination" => "神奈川県川崎市"
  },
  %{
    "days_ago" => 2,
    "start" => 52_300,
    "distance" => 95,
    "status" => "approved",
    "destination" => "埼玉県さいたま市"
  },
  %{
    "days_ago" => 3,
    "start" => 52_395,
    "distance" => 140,
    "status" => "rejected",
    "destination" => "千葉県市川市"
  }
]

if tky_vehicle && tky_driver do
  for attrs <- report_seeds do
    operation_date = Date.add(today, -attrs["days_ago"])
    departed_at = DateTime.new!(operation_date, ~T[00:00:00]) |> DateTime.add(-2, :hour)
    returned_at = DateTime.add(departed_at, 9, :hour)

    existing =
      OperationReports.list_operation_reports(admin_scope, %{
        "from" => Date.to_iso8601(operation_date),
        "to" => Date.to_iso8601(operation_date),
        "vehicle_id" => tky_vehicle.id
      })

    if existing.total_entries == 0 do
      {:ok, report} =
        OperationReports.create_operation_report(admin_scope, %{
          "vehicle_id" => tky_vehicle.id,
          "driver_id" => tky_driver.id,
          "operation_date" => Date.to_iso8601(operation_date),
          "departed_at" => DateTime.to_iso8601(departed_at),
          "returned_at" => DateTime.to_iso8601(returned_at),
          "start_odometer" => attrs["start"],
          "end_odometer" => attrs["start"] + attrs["distance"],
          "destination" => attrs["destination"],
          "cargo_type" => "一般貨物",
          "rest_minutes" => 60,
          "refuelings" => %{
            "0" => %{
              "refueled_at" => DateTime.to_iso8601(DateTime.add(departed_at, 3, :hour)),
              "liters" => "48.5",
              "amount_yen" => 7760,
              "odometer" => attrs["start"] + div(attrs["distance"], 2)
            }
          }
        })

      report =
        case attrs["status"] do
          "draft" ->
            report

          "submitted" ->
            {:ok, submitted} = OperationReports.submit_report(admin_scope, report)
            submitted

          "approved" ->
            {:ok, submitted} = OperationReports.submit_report(admin_scope, report)
            {:ok, approved} = OperationReports.approve_report(admin_scope, submitted)
            approved

          "rejected" ->
            {:ok, submitted} = OperationReports.submit_report(admin_scope, report)

            {:ok, rejected} =
              OperationReports.reject_report(
                admin_scope,
                submitted,
                "帰着時の走行距離計を確認してください。"
              )

            rejected
        end

      IO.puts("created operation report: #{report.operation_date} #{report.status}")
    else
      IO.puts("skipped operation report: #{operation_date}")
    end
  end
end

# --- 事故・ヒヤリ ---
# 報告直後・分析中・完了の3状態を作り、画面の出し分けを確認できるようにする。
incidents = [
  %{
    "category" => "near_miss",
    "place" => "東京都江東区 青海ランプ付近",
    "weather" => "rain",
    "description" => "合流時に後方の車両を見落とし、急ブレーキで回避した。",
    "progress" => "reported"
  },
  %{
    "category" => "single",
    "place" => "東京都江東区 青海営業所構内",
    "weather" => "clear",
    "description" => "後退時に縁石へ乗り上げ、左後輪付近から異音がする。",
    "progress" => "analyzing"
  },
  %{
    "category" => "property",
    "place" => "東京都港区 芝公園2丁目",
    "weather" => "cloudy",
    "description" => "駐車場で切り返し中に相手車両の前バンパーへ接触した。",
    "progress" => "closed"
  }
]

manager_scope = Accounts.get_user_by_email("manager@example.com") |> Scope.for_user()

for {attrs, index} <- Enum.with_index(incidents) do
  if Incidents.list_incidents(admin_scope, %{"q" => attrs["place"]}).total_entries == 0 do
    occurred_at =
      DateTime.utc_now()
      |> DateTime.add(-(index + 1) * 24 * 3600, :second)
      |> DateTime.truncate(:second)

    {:ok, incident} =
      Incidents.create_incident(
        manager_scope,
        Map.merge(attrs, %{
          "vehicle_id" => tky_vehicle.id,
          "driver_id" => tky_driver.id,
          "occurred_at" => DateTime.to_iso8601(occurred_at)
        })
      )

    incident =
      case attrs["progress"] do
        "reported" ->
          incident

        "analyzing" ->
          {:ok, analyzing} = Incidents.start_analysis(manager_scope, incident)
          analyzing

        "closed" ->
          {:ok, analyzing} = Incidents.start_analysis(manager_scope, incident)

          {:ok, reported} =
            Incidents.report_countermeasure(manager_scope, analyzing, %{
              "direct_cause" => "後方確認が不十分だった",
              "background_factor" => "納品時刻に追われ、手順を省略していた",
              "countermeasure" => "構内の後退は誘導者を付ける手順に変更する",
              "countermeasure_owner" => "運行 花子"
            })

          {:ok, closed} = Incidents.approve_incident(admin_scope, reported)
          {:ok, shared} = Incidents.share_incident(admin_scope, closed, true)
          shared
      end

    IO.puts("created incident: #{incident.place} (#{incident.status})")
  else
    IO.puts("skipped incident: #{attrs["place"]}")
  end
end
