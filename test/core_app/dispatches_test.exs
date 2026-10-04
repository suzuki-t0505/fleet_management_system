defmodule CoreApp.DispatchesTest do
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.DispatchesFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.ShippersFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.AuditLogs.AuditLog
  alias CoreApp.Dispatches
  alias CoreApp.Dispatches.Dispatch

  defp setup_offices(_context) do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    manager_a = manager_fixture(%{office_id: office_a.id}) |> Scope.for_user()
    manager_b = manager_fixture(%{office_id: office_b.id}) |> Scope.for_user()
    admin = admin_fixture(%{office_id: office_a.id}) |> Scope.for_user()

    %{
      office_a: office_a,
      office_b: office_b,
      manager_a: manager_a,
      manager_b: manager_b,
      admin: admin
    }
  end

  defp deliveries(list) do
    list
    |> Enum.with_index()
    |> Map.new(fn {{destination, fare}, index} ->
      {to_string(index), %{"destination" => destination, "fare_yen" => fare}}
    end)
  end

  describe "create_dispatch/3" do
    setup :setup_offices

    test "コース一括で登録でき、合計はコース料金と高速料金の和になる", %{manager_a: scope, office_a: office} do
      attrs = dispatch_attributes_for(scope)

      assert {:ok, %Dispatch{} = dispatch} = Dispatches.create_dispatch(scope, attrs)

      assert dispatch.office_id == office.id
      assert dispatch.created_by_user_id == scope.user.id
      assert dispatch.pricing_type == :course_total
      assert Dispatches.total_amount_yen(dispatch) == 31_500
    end

    test "コース一括でも配送先を複数登録できる（配送料金は持たない）", %{manager_a: scope} do
      attrs =
        dispatch_attributes_for(scope, %{
          "deliveries" => deliveries([{"東京", "9999"}, {"横浜", ""}])
        })

      {:ok, dispatch} = Dispatches.create_dispatch(scope, attrs)

      assert [%{destination: "東京", fare_yen: nil, position: 1}, %{destination: "横浜", position: 2}] =
               dispatch.deliveries

      assert Dispatches.total_amount_yen(dispatch) == 31_500
    end

    test "配送ごとの合計は配送料金の合計と高速料金の和になる", %{manager_a: scope} do
      attrs =
        dispatch_attributes_for(scope, %{
          "pricing_type" => "per_delivery",
          "course_fare_yen" => "99999",
          "deliveries" => deliveries([{"東京", "10000"}, {"横浜", "8000"}])
        })

      {:ok, dispatch} = Dispatches.create_dispatch(scope, attrs)

      # 使わない側のコース料金は nil に正規化される（D-3）
      assert dispatch.course_fare_yen == nil
      assert Dispatches.total_amount_yen(dispatch) == 19_500
    end

    test "運行管理者は他拠点の車両を指定できない", %{manager_a: scope, manager_b: other} do
      attrs = dispatch_attributes_for(other)

      assert {:error, changeset} = Dispatches.create_dispatch(scope, attrs)
      assert "は自拠点の車両を選択してください" in errors_on(changeset).vehicle_id
    end

    test "管理者は他拠点の配車を登録でき、拠点は車両に従う", %{admin: admin, manager_b: other, office_b: office_b} do
      attrs = dispatch_attributes_for(other)

      assert {:ok, dispatch} = Dispatches.create_dispatch(admin, attrs)
      assert dispatch.office_id == office_b.id
    end

    test "必須項目が無い場合はエラーを返す", %{manager_a: scope} do
      assert {:error, changeset} = Dispatches.create_dispatch(scope, %{})

      errors = errors_on(changeset)
      assert "can't be blank" in errors.title
      assert "can't be blank" in errors.shipper_id
      assert "can't be blank" in errors.vehicle_id
      assert "can't be blank" in errors.driver_id
      assert "can't be blank" in errors.started_at
    end

    test "終了日時が開始日時以前だとエラーになる（D-1）", %{manager_a: scope} do
      attrs = dispatch_attributes_for(scope, %{"ended_at" => "2026-10-01T09:00:00Z"})

      assert {:error, changeset} = Dispatches.create_dispatch(scope, attrs)
      assert "は配送開始日時より後の日時を入力してください" in errors_on(changeset).ended_at
    end

    test "フォームの日時（タイムゾーン無し）はJSTとして扱う", %{manager_a: scope} do
      attrs =
        dispatch_attributes_for(scope, %{
          "started_at" => "2026-10-01T09:00",
          "ended_at" => "2026-10-01T12:00"
        })

      {:ok, dispatch} = Dispatches.create_dispatch(scope, attrs)

      assert dispatch.started_at == ~U[2026-10-01 00:00:00Z]
      assert dispatch.ended_at == ~U[2026-10-01 03:00:00Z]
    end

    test "コース一括はコース料金が必須", %{manager_a: scope} do
      attrs = dispatch_attributes_for(scope, %{"course_fare_yen" => ""})

      assert {:error, changeset} = Dispatches.create_dispatch(scope, attrs)
      assert "コース料金を入力してください" in errors_on(changeset).course_fare_yen
    end

    test "配送ごとは配送明細が1件以上必要", %{manager_a: scope} do
      attrs = dispatch_attributes_for(scope, %{"pricing_type" => "per_delivery"})

      assert {:error, changeset} = Dispatches.create_dispatch(scope, attrs)
      assert "を1件以上入力してください" in errors_on(changeset).deliveries
    end

    test "配送ごとは各明細の配送料金が必須", %{manager_a: scope} do
      attrs =
        dispatch_attributes_for(scope, %{
          "pricing_type" => "per_delivery",
          "deliveries" => deliveries([{"東京", ""}])
        })

      assert {:error, changeset} = Dispatches.create_dispatch(scope, attrs)

      assert %{deliveries: [%{fare_yen: ["can't be blank"]}]} = errors_on(changeset)
    end

    test "配送先が空の明細はエラーになる", %{manager_a: scope} do
      attrs = dispatch_attributes_for(scope, %{"deliveries" => deliveries([{"", ""}])})

      assert {:error, changeset} = Dispatches.create_dispatch(scope, attrs)
      assert %{deliveries: [%{destination: ["can't be blank"]}]} = errors_on(changeset)
    end

    test "料金は負の値にできない", %{manager_a: scope} do
      attrs = dispatch_attributes_for(scope, %{"toll_yen" => "-1", "course_fare_yen" => "-5"})

      assert {:error, changeset} = Dispatches.create_dispatch(scope, attrs)
      errors = errors_on(changeset)
      assert errors.toll_yen != []
      assert errors.course_fare_yen != []
    end

    test "高速料金が空欄なら0円になる", %{manager_a: scope} do
      attrs = dispatch_attributes_for(scope, %{"toll_yen" => ""})

      {:ok, dispatch} = Dispatches.create_dispatch(scope, attrs)
      assert dispatch.toll_yen == 0
    end

    test "他拠点の荷主は指定できない（D-5）", %{manager_a: scope, manager_b: other} do
      foreign = shipper_fixture(other)
      attrs = dispatch_attributes_for(scope, %{"shipper_id" => foreign.id})

      assert {:error, changeset} = Dispatches.create_dispatch(scope, attrs)
      assert "は配車と同じ拠点の荷主を選択してください" in errors_on(changeset).shipper_id
    end

    test "他拠点のドライバーは指定できない（D-5）", %{manager_a: scope, manager_b: other} do
      foreign = driver_fixture(other)
      attrs = dispatch_attributes_for(scope, %{"driver_id" => foreign.id})

      assert {:error, changeset} = Dispatches.create_dispatch(scope, attrs)
      assert "は配車と同じ拠点のドライバーを選択してください" in errors_on(changeset).driver_id
    end

    test "無効な荷主は指定できない（D-6）", %{manager_a: scope} do
      inactive = shipper_fixture(scope, %{"status" => "inactive"})
      attrs = dispatch_attributes_for(scope, %{"shipper_id" => inactive.id})

      assert {:error, changeset} = Dispatches.create_dispatch(scope, attrs)
      assert "は無効なため選択できません" in errors_on(changeset).shipper_id
    end

    test "一般利用者は登録できない", %{office_a: office, manager_a: manager} do
      member = user_fixture(%{office_id: office.id}) |> Scope.for_user()

      assert {:error, :unauthorized} =
               Dispatches.create_dispatch(member, dispatch_attributes_for(manager))
    end

    test "監査ログが記録される", %{manager_a: scope} do
      {:ok, dispatch} = Dispatches.create_dispatch(scope, dispatch_attributes_for(scope))

      log = Repo.get_by!(AuditLog, resource_type: "dispatch", resource_id: dispatch.id)
      assert log.action == :create
    end

    test "失敗時は配車も監査ログも残さない", %{manager_a: scope} do
      {:error, _} = Dispatches.create_dispatch(scope, %{})

      assert Repo.all(Dispatch) == []
      refute Repo.get_by(AuditLog, resource_type: "dispatch")
    end
  end

  describe "update_dispatch/4" do
    setup :setup_offices

    test "料金方式をコース一括から配送ごとに切り替えると、コース料金は消える（D-3）", %{manager_a: scope} do
      dispatch = dispatch_fixture(scope)

      {:ok, updated} =
        Dispatches.update_dispatch(scope, dispatch, %{
          "pricing_type" => "per_delivery",
          "deliveries" => deliveries([{"東京", "7000"}])
        })

      assert updated.course_fare_yen == nil
      assert Dispatches.total_amount_yen(updated) == 8_500
    end

    test "配送ごとからコース一括に切り替えると、各明細の配送料金は消える（D-3）", %{manager_a: scope} do
      dispatch =
        dispatch_fixture(scope, %{
          "pricing_type" => "per_delivery",
          "deliveries" => deliveries([{"東京", "7000"}])
        })

      [delivery] = dispatch.deliveries

      {:ok, updated} =
        Dispatches.update_dispatch(scope, dispatch, %{
          "pricing_type" => "course_total",
          "course_fare_yen" => "20000",
          "deliveries" => %{"0" => %{"id" => delivery.id, "destination" => "東京"}}
        })

      assert [%{fare_yen: nil}] = updated.deliveries
      assert Dispatches.total_amount_yen(updated) == 21_500
    end

    test "明細を削除できる", %{manager_a: scope} do
      dispatch =
        dispatch_fixture(scope, %{
          "pricing_type" => "per_delivery",
          "deliveries" => deliveries([{"東京", "7000"}, {"横浜", "3000"}])
        })

      [first, second] = dispatch.deliveries

      {:ok, updated} =
        Dispatches.update_dispatch(scope, dispatch, %{
          "deliveries" => %{
            "0" => %{"id" => first.id, "destination" => "東京", "fare_yen" => "7000"}
          },
          "deliveries_drop" => ["1"]
        })

      refute second.id in Enum.map(updated.deliveries, & &1.id)
    end

    test "監査ログが記録される", %{manager_a: scope} do
      dispatch = dispatch_fixture(scope)

      {:ok, _} = Dispatches.update_dispatch(scope, dispatch, %{"title" => "変更後"})

      assert Repo.get_by!(AuditLog,
               resource_type: "dispatch",
               resource_id: dispatch.id,
               action: :update
             )
    end

    test "他拠点の運行管理者は更新できない", %{manager_a: scope, manager_b: other} do
      dispatch = dispatch_fixture(scope)

      assert {:error, :unauthorized} =
               Dispatches.update_dispatch(other, dispatch, %{"title" => "乗っ取り"})
    end

    test "既に紐付いている荷主が無効化されていても更新できる（D-6）", %{manager_a: scope} do
      dispatch = dispatch_fixture(scope)
      shipper = CoreApp.Shippers.get_shipper!(scope, dispatch.shipper_id)
      {:ok, _} = CoreApp.Shippers.update_shipper(scope, shipper, %{"status" => "inactive"})

      assert {:ok, _} = Dispatches.update_dispatch(scope, dispatch, %{"title" => "変更後"})
    end
  end

  describe "get_dispatch!/2" do
    setup :setup_offices

    test "他拠点の配車は取得できない", %{manager_a: a, manager_b: b} do
      dispatch = dispatch_fixture(b)

      assert_raise Ecto.NoResultsError, fn -> Dispatches.get_dispatch!(a, dispatch.id) end
    end

    test "管理者は他拠点の配車も取得できる", %{admin: admin, manager_b: b} do
      dispatch = dispatch_fixture(b)

      assert Dispatches.get_dispatch!(admin, dispatch.id).id == dispatch.id
    end

    test "一般利用者は自分に割り当てられた配車だけ取得できる", %{manager_a: manager, office_a: office} do
      member_user = user_fixture(%{office_id: office.id})
      driver = driver_fixture(manager, %{"user_id" => member_user.id})
      member = member_user |> CoreApp.Repo.preload(:driver, force: true) |> Scope.for_user()

      mine = dispatch_fixture(manager, %{"driver_id" => driver.id})
      others = dispatch_fixture(manager)

      assert member.driver_id == driver.id
      assert Dispatches.get_dispatch!(member, mine.id).id == mine.id

      assert_raise Ecto.NoResultsError, fn -> Dispatches.get_dispatch!(member, others.id) end
    end
  end

  describe "list_dispatches/2" do
    setup :setup_offices

    test "自拠点の配車だけ返す", %{manager_a: a, manager_b: b} do
      mine = dispatch_fixture(a)
      dispatch_fixture(b)

      assert [%{id: id}] = Dispatches.list_dispatches(a).entries
      assert id == mine.id
    end

    test "運転者が紐付いていない一般利用者には何も返さない", %{manager_a: a, office_a: office} do
      dispatch_fixture(a)
      member = user_fixture(%{office_id: office.id}) |> Scope.for_user()

      assert Dispatches.list_dispatches(member).entries == []
    end

    test "一般利用者には自分の配車だけ返す", %{manager_a: manager, office_a: office} do
      member_user = user_fixture(%{office_id: office.id})
      driver = driver_fixture(manager, %{"user_id" => member_user.id})
      member = member_user |> CoreApp.Repo.preload(:driver, force: true) |> Scope.for_user()

      mine = dispatch_fixture(manager, %{"driver_id" => driver.id})
      dispatch_fixture(manager)

      assert [%{id: id}] = Dispatches.list_dispatches(member).entries
      assert id == mine.id
    end

    test "開始日時の降順で並ぶ", %{manager_a: a} do
      older =
        dispatch_fixture(a, %{
          "started_at" => "2026-09-01T00:00:00Z",
          "ended_at" => "2026-09-01T03:00:00Z"
        })

      newer =
        dispatch_fixture(a, %{
          "started_at" => "2026-10-01T00:00:00Z",
          "ended_at" => "2026-10-01T03:00:00Z"
        })

      assert [first, second] = Dispatches.list_dispatches(a).entries
      assert first.id == newer.id
      assert second.id == older.id
    end

    test "期間はJSTの開始日で絞り込む", %{manager_a: a} do
      # 2026-09-30 15:30 UTC = 2026-10-01 00:30 JST
      jst_oct_first =
        dispatch_fixture(a, %{
          "started_at" => "2026-09-30T15:30:00Z",
          "ended_at" => "2026-09-30T18:00:00Z"
        })

      dispatch_fixture(a, %{
        "started_at" => "2026-09-30T14:30:00Z",
        "ended_at" => "2026-09-30T15:00:00Z"
      })

      params = %{"from" => "2026-10-01", "to" => "2026-10-01"}
      assert [%{id: id}] = Dispatches.list_dispatches(a, params).entries
      assert id == jst_oct_first.id
    end

    test "荷主・車両・ドライバーで絞り込める", %{manager_a: a} do
      target = dispatch_fixture(a)
      dispatch_fixture(a)

      for {key, value} <- [
            {"shipper_id", target.shipper_id},
            {"vehicle_id", target.vehicle_id},
            {"driver_id", target.driver_id}
          ] do
        assert [%{id: id}] = Dispatches.list_dispatches(a, %{key => value}).entries
        assert id == target.id
      end
    end

    test "キーワードでタイトル・荷主名・配送先を検索できる", %{manager_a: a} do
      shipper = shipper_fixture(a, %{"name" => "北海道物流"})
      by_title = dispatch_fixture(a, %{"title" => "朝便ルート"})
      by_shipper = dispatch_fixture(a, %{"shipper_id" => shipper.id})

      by_destination =
        dispatch_fixture(a, %{"deliveries" => deliveries([{"福岡センター", ""}])})

      ids = fn q -> Enum.map(Dispatches.list_dispatches(a, %{"q" => q}).entries, & &1.id) end

      assert ids.("朝便") == [by_title.id]
      assert ids.("北海道") == [by_shipper.id]
      assert ids.("福岡") == [by_destination.id]
    end
  end

  describe "warnings/2" do
    setup :setup_offices

    test "同じ車両で時間帯が重なる場合は警告する（D-4）", %{manager_a: a} do
      existing = dispatch_fixture(a)

      attrs =
        dispatch_attributes_for(a, %{
          "vehicle_id" => existing.vehicle_id,
          "started_at" => "2026-10-01T11:00:00Z",
          "ended_at" => "2026-10-01T14:00:00Z"
        })

      changeset = Dispatches.change_dispatch(%Dispatch{deliveries: []}, a, attrs)

      assert ["同じ車両で時間帯が重なる配車が既に登録されています。"] = Dispatches.warnings(a, changeset)
    end

    test "同じドライバーで時間帯が重なる場合は警告する（D-4）", %{manager_a: a} do
      existing = dispatch_fixture(a)

      attrs =
        dispatch_attributes_for(a, %{
          "driver_id" => existing.driver_id,
          "started_at" => "2026-10-01T10:00:00Z",
          "ended_at" => "2026-10-01T11:00:00Z"
        })

      changeset = Dispatches.change_dispatch(%Dispatch{deliveries: []}, a, attrs)

      assert ["同じドライバーで時間帯が重なる配車が既に登録されています。"] = Dispatches.warnings(a, changeset)
    end

    test "終了時刻と開始時刻が一致するだけなら警告しない", %{manager_a: a} do
      existing = dispatch_fixture(a)

      attrs =
        dispatch_attributes_for(a, %{
          "vehicle_id" => existing.vehicle_id,
          "driver_id" => existing.driver_id,
          "started_at" => "2026-10-01T12:00:00Z",
          "ended_at" => "2026-10-01T15:00:00Z"
        })

      changeset = Dispatches.change_dispatch(%Dispatch{deliveries: []}, a, attrs)

      assert Dispatches.warnings(a, changeset) == []
    end

    test "自分自身との重なりは警告しない", %{manager_a: a} do
      existing = dispatch_fixture(a)

      changeset = Dispatches.change_dispatch(existing, a, %{"title" => "変更"})

      assert Dispatches.warnings(a, changeset) == []
    end

    test "日時が未入力なら警告しない", %{manager_a: a} do
      changeset = Dispatches.change_dispatch(%Dispatch{deliveries: []}, a, %{})

      assert Dispatches.warnings(a, changeset) == []
    end
  end

  describe "total_amount_yen/1" do
    setup :setup_offices

    test "changesetの入力内容からもプレビューできる", %{manager_a: a} do
      attrs =
        dispatch_attributes_for(a, %{
          "pricing_type" => "per_delivery",
          "deliveries" => deliveries([{"東京", "10000"}, {"横浜", "8000"}])
        })

      changeset = Dispatches.change_dispatch(%Dispatch{deliveries: []}, a, attrs)

      assert Dispatches.total_amount_yen(changeset) == 19_500
    end

    test "未入力の金額は0円として数える" do
      assert Dispatch.total_amount_yen(%Dispatch{pricing_type: :course_total}) == 0

      assert Dispatch.total_amount_yen(%Dispatch{
               pricing_type: :per_delivery,
               toll_yen: 500,
               deliveries: [%CoreApp.Dispatches.Delivery{fare_yen: nil}]
             }) == 500
    end
  end
end
