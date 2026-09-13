# 開発環境用の初期データ。
#
#     docker compose run --rm web mix run priv/repo/seeds.exs
#
# 再実行してもエラーにならないよう、既存レコードがある場合は作成をスキップする。
# ここで設定するパスワードは開発環境専用。本番環境では絶対に使用しない。

alias CoreApp.Accounts
alias CoreApp.Accounts.Scope
alias CoreApp.Offices
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
