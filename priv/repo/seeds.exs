# 開発環境用の初期データ。
#
#     docker compose run --rm web mix run priv/repo/seeds.exs
#
# 再実行してもエラーにならないよう、既存レコードがある場合は作成をスキップする。
# ここで設定するパスワードは開発環境専用。本番環境では絶対に使用しない。

alias CoreApp.Accounts
alias CoreApp.Offices

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
