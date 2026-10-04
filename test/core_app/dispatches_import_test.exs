defmodule CoreApp.DispatchesImportTest do
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.ShippersFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.AuditLogs.AuditLog
  alias CoreApp.Dispatches
  alias CoreApp.Dispatches.Dispatch

  defp setup_masters(_context) do
    office = office_fixture(%{"name" => "A営業所"})
    scope = manager_fixture(%{office_id: office.id}) |> Scope.for_user()

    vehicle = vehicle_fixture(scope, %{"plate_number" => "品川 100 あ 12-34"})
    driver = driver_fixture(scope, %{"code" => "D001", "name" => "山田 太郎"})
    shipper = shipper_fixture(scope, %{"code" => "S001", "name" => "株式会社テスト運輸"})

    %{office: office, scope: scope, vehicle: vehicle, driver: driver, shipper: shipper}
  end

  defp row(attrs \\ %{}) do
    Map.merge(
      %{
        "ref" => "2",
        "title" => "横浜-大阪",
        "shipper" => "株式会社テスト運輸",
        "vehicle" => "品川100あ12-34",
        "driver" => "山田太郎",
        "started_at" => "2026-10-04 09:00",
        "ended_at" => "2026-10-04T18:00",
        "course_fare_yen" => 50_000,
        "toll_yen" => 3_000
      },
      attrs
    )
  end

  describe "validate_import/2" do
    setup :setup_masters

    test "表記ゆれ（全角半角・空白）を吸収して名称を解決し、保存はしない", %{scope: scope} do
      before_count = Repo.aggregate(Dispatch, :count)

      assert {:ok, [result]} =
               Dispatches.validate_import(scope, [row(%{"vehicle" => "品川１００あ12－34"})])

      assert result.errors == []
      assert result.ref == "2"
      assert result.total_amount_yen == 53_000
      assert Repo.aggregate(Dispatch, :count) == before_count
    end

    test "コードでも解決できる", %{scope: scope} do
      assert {:ok, [result]} =
               Dispatches.validate_import(scope, [row(%{"driver" => "d001", "shipper" => "S001"})])

      assert result.errors == []
    end

    test "未登録の荷主・車両・ドライバーは、まとめてエラーにする（自動作成しない）", %{scope: scope} do
      assert {:ok, [result]} =
               Dispatches.validate_import(scope, [
                 row(%{"shipper" => "新規荷主", "vehicle" => "存在しない", "driver" => "誰か"})
               ])

      assert length(result.errors) == 3
      assert Enum.any?(result.errors, &(&1 =~ "荷主「新規荷主」は登録されていません"))
      assert Enum.any?(result.errors, &(&1 =~ "車両「存在しない」"))
      assert Enum.any?(result.errors, &(&1 =~ "ドライバー「誰か」"))
      assert Repo.aggregate(CoreApp.Shippers.Shipper, :count) == 1
    end

    test "同名が複数あればエラーにする", %{scope: scope} do
      driver_fixture(scope, %{"code" => "D002", "name" => "山田 太郎"})

      assert {:ok, [result]} = Dispatches.validate_import(scope, [row(%{"driver" => "山田太郎"})])

      assert [message] = result.errors
      assert message =~ "複数"
    end

    test "未入力はエラーにする", %{scope: scope} do
      assert {:ok, [result]} = Dispatches.validate_import(scope, [row(%{"vehicle" => ""})])

      assert result.errors == ["車両が未入力です"]
    end

    test "入力の検証エラーを日本語の項目名で返す", %{scope: scope} do
      assert {:ok, [result]} =
               Dispatches.validate_import(scope, [
                 row(%{"title" => "", "ended_at" => "2026-10-04T08:00", "course_fare_yen" => nil})
               ])

      assert Enum.any?(result.errors, &String.starts_with?(&1, "配送タイトル "))
      assert Enum.any?(result.errors, &String.starts_with?(&1, "配送終了日時 "))
      assert Enum.any?(result.errors, &String.starts_with?(&1, "コース料金 "))
    end

    test "配送ごとの料金方式は、料金方式を省略しても配送料金から判定する", %{scope: scope} do
      deliveries = [
        %{"destination" => "大阪", "fare_yen" => 20_000},
        %{"destination" => "神戸", "fare_yen" => 15_000}
      ]

      assert {:ok, [result]} =
               Dispatches.validate_import(scope, [
                 row(%{"course_fare_yen" => nil, "deliveries" => deliveries})
               ])

      assert result.errors == []
      assert result.total_amount_yen == 38_000
    end

    test "配送明細のエラーは配送明細の番号つきで返す", %{scope: scope} do
      deliveries = [%{"destination" => "大阪"}, %{"destination" => ""}]

      assert {:ok, [result]} =
               Dispatches.validate_import(scope, [
                 row(%{"deliveries" => deliveries, "pricing_type" => "per_delivery"})
               ])

      assert Enum.any?(result.errors, &String.starts_with?(&1, "配送明細1.配送料金"))
      assert Enum.any?(result.errors, &String.starts_with?(&1, "配送明細2.配送先"))
    end

    test "登録済みの配車と同じ行は二重登録としてエラーにする", %{scope: scope} do
      assert {:ok, _created} = Dispatches.import_dispatches(scope, [row()])

      assert {:ok, [result]} = Dispatches.validate_import(scope, [row()])
      assert [message] = result.errors
      assert message =~ "既に登録されています"
    end

    test "入力内の同じ行はエラー、時間帯が重なる行は警告にする", %{scope: scope} do
      overlapping = row(%{"title" => "別便", "started_at" => "2026-10-04T10:00"})

      assert {:ok, [first, second, third]} =
               Dispatches.validate_import(scope, [row(), overlapping, row()])

      assert first.errors == []
      assert second.errors == []
      assert Enum.any?(second.warnings, &(&1 =~ "入力内の1行目と同じ車両"))
      assert Enum.any?(second.warnings, &(&1 =~ "入力内の1行目と同じドライバー"))
      assert third.errors == ["入力内の1行目と同じ配車です"]
    end

    test "登録済みの配車と時間帯が重なる場合は警告にする", %{scope: scope} do
      assert {:ok, _created} = Dispatches.import_dispatches(scope, [row()])

      assert {:ok, [result]} = Dispatches.validate_import(scope, [row(%{"title" => "別便"})])

      assert result.errors == []
      assert length(result.warnings) == 2
    end

    test "運行管理者未満は使えない", %{office: office} do
      member = user_fixture(%{office_id: office.id, role: :member}) |> Scope.for_user()

      assert Dispatches.validate_import(member, [row()]) == {:error, :unauthorized}
    end

    test "空と上限超過は受け付けない", %{scope: scope} do
      assert Dispatches.validate_import(scope, []) == {:error, :empty}

      rows = List.duplicate(row(), Dispatches.max_import_rows() + 1)
      assert Dispatches.validate_import(scope, rows) == {:error, :too_many_rows}
    end

    test "他拠点のマスタは名称が同じでも解決しない", %{scope: scope} do
      other_office = office_fixture(%{"name" => "B営業所"})
      other = manager_fixture(%{office_id: other_office.id}) |> Scope.for_user()
      vehicle_fixture(other, %{"plate_number" => "横浜300い5678"})

      assert {:ok, [result]} =
               Dispatches.validate_import(scope, [row(%{"vehicle" => "横浜300い5678"})])

      assert Enum.any?(result.errors, &(&1 =~ "車両「横浜300い5678」は登録されていません"))
    end

    test "管理者は車両の拠点のドライバー・荷主で解決する", %{office: office, vehicle: vehicle} do
      other_office = office_fixture(%{"name" => "B営業所"})
      other = manager_fixture(%{office_id: other_office.id}) |> Scope.for_user()
      driver_fixture(other, %{"code" => "X1", "name" => "山田 太郎"})
      admin = admin_fixture(%{office_id: office.id}) |> Scope.for_user()

      assert {:ok, [result]} =
               Dispatches.validate_import(admin, [row(%{"vehicle" => vehicle.plate_number})])

      assert result.errors == []
    end
  end

  describe "import_dispatches/3" do
    setup :setup_masters

    test "全行が有効なら登録し、車両の拠点・登録者・監査ログが設定される",
         %{scope: scope, office: office, vehicle: vehicle} do
      deliveries = [%{"destination" => "大阪", "loading_at" => "2026-10-04 09:30"}]

      assert {:ok, [created, _second]} =
               Dispatches.import_dispatches(
                 scope,
                 [
                   row(%{"deliveries" => deliveries}),
                   row(%{
                     "title" => "別日",
                     "started_at" => "2026-10-05T09:00",
                     "ended_at" => "2026-10-05T12:00"
                   })
                 ],
                 ip_address: "203.0.113.5"
               )

      dispatch = created.dispatch
      assert dispatch.office_id == office.id
      assert dispatch.vehicle_id == vehicle.id
      assert dispatch.created_by_user_id == scope.user.id
      # JST 9:00 は UTC 0:00
      assert dispatch.started_at == ~U[2026-10-04 00:00:00Z]
      assert [%{destination: "大阪", loading_at: ~U[2026-10-04 00:30:00Z]}] = dispatch.deliveries

      log = Repo.get_by!(AuditLog, resource_type: "dispatch", resource_id: dispatch.id)
      assert log.action == :create
      assert log.ip_address == "203.0.113.5"
    end

    test "1行でもエラーなら何も登録しない", %{scope: scope} do
      bad = row(%{"title" => "別便", "driver" => "存在しない"})

      assert {:error, {:invalid, [first, second]}} =
               Dispatches.import_dispatches(scope, [row(), bad])

      assert first.errors == []
      assert second.errors != []
      assert Repo.aggregate(Dispatch, :count) == 0
    end

    test "同じ内容を再実行しても二重登録されない", %{scope: scope} do
      assert {:ok, [_created]} = Dispatches.import_dispatches(scope, [row()])
      assert {:error, {:invalid, [result]}} = Dispatches.import_dispatches(scope, [row()])

      assert result.errors != []
      assert Repo.aggregate(Dispatch, :count) == 1
    end
  end
end
