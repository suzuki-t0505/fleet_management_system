defmodule CoreApp.DispatchDeliveryTimesTest do
  @moduledoc "配送先の荷積み・荷降ろし日時（B-1〜B-4）のテストです。"
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.DispatchesFixtures
  import CoreApp.OfficesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Dispatches
  alias CoreApp.Exports

  # 配車は 2026-10-01 09:00〜12:00 UTC
  setup do
    office = office_fixture(%{"name" => "A営業所"})
    scope = manager_fixture(%{office_id: office.id}) |> Scope.for_user()

    %{scope: scope}
  end

  defp delivery(attrs), do: %{"0" => Map.merge(%{"destination" => "東京"}, attrs)}

  defp create(scope, deliveries, extra \\ %{}) do
    Dispatches.create_dispatch(
      scope,
      dispatch_attributes_for(scope, Map.merge(%{"deliveries" => deliveries}, extra))
    )
  end

  test "荷積み・荷降ろしは任意で、保存できる（B-1）", %{scope: scope} do
    assert {:ok, %{deliveries: [d]}} = create(scope, delivery(%{}))
    assert d.loading_at == nil
    assert d.unloading_at == nil

    assert {:ok, %{deliveries: [d]}} =
             create(scope, delivery(%{"loading_at" => "2026-10-01T09:30:00Z"}))

    assert d.loading_at == ~U[2026-10-01 09:30:00Z]
    assert d.unloading_at == nil

    assert {:ok, %{deliveries: [d]}} =
             create(
               scope,
               delivery(%{"loading_at" => "", "unloading_at" => "2026-10-01T11:00:00Z"})
             )

    assert d.loading_at == nil
    assert d.unloading_at == ~U[2026-10-01 11:00:00Z]
  end

  test "荷降ろしが荷積み以前だとエラー（B-2）", %{scope: scope} do
    for unloading <- ["2026-10-01T10:00:00Z", "2026-10-01T09:30:00Z"] do
      assert {:error, changeset} =
               create(
                 scope,
                 delivery(%{"loading_at" => "2026-10-01T10:00:00Z", "unloading_at" => unloading})
               )

      assert %{deliveries: [%{unloading_at: ["は荷積み日時より後の日時を入力してください"]}]} =
               errors_on(changeset)
    end
  end

  test "配送開始〜終了の範囲外はエラー、境界は許可する（B-3）", %{scope: scope} do
    assert {:ok, _} =
             create(
               scope,
               delivery(%{
                 "loading_at" => "2026-10-01T09:00:00Z",
                 "unloading_at" => "2026-10-01T12:00:00Z"
               })
             )

    assert {:error, changeset} =
             create(
               scope,
               delivery(%{
                 "loading_at" => "2026-10-01T08:59:00Z",
                 "unloading_at" => "2026-10-01T12:01:00Z"
               })
             )

    assert %{
             deliveries: [
               %{
                 loading_at: ["は配送開始〜終了の間の日時を入力してください"],
                 unloading_at: ["は配送開始〜終了の間の日時を入力してください"]
               }
             ]
           } = errors_on(changeset)
  end

  test "親の配送日時が未入力なら範囲は検証しない（親のエラーだけが出る）", %{scope: scope} do
    assert {:error, changeset} =
             create(scope, delivery(%{"loading_at" => "2030-01-01T00:00:00Z"}), %{
               "started_at" => ""
             })

    errors = errors_on(changeset)
    assert "can't be blank" in errors.started_at
    refute Map.has_key?(errors, :deliveries)
  end

  test "JST入力はUTCで保存される", %{scope: scope} do
    # 配車 09:00〜12:00 UTC = 18:00〜21:00 JST
    assert {:ok, %{deliveries: [d]}} =
             create(
               scope,
               delivery(%{
                 "loading_at" => "2026-10-01T19:00",
                 "unloading_at" => "2026-10-01T20:30"
               }),
               %{"started_at" => "2026-10-01T18:00", "ended_at" => "2026-10-01T21:00"}
             )

    assert d.loading_at == ~U[2026-10-01 10:00:00Z]
    assert d.unloading_at == ~U[2026-10-01 11:30:00Z]
  end

  test "更新で時刻を変更・消去できる", %{scope: scope} do
    {:ok, dispatch} =
      create(scope, delivery(%{"loading_at" => "2026-10-01T09:30:00Z"}))

    [d] = dispatch.deliveries

    {:ok, updated} =
      Dispatches.update_dispatch(scope, dispatch, %{
        "deliveries" => %{
          "0" => %{
            "id" => d.id,
            "destination" => "東京",
            "loading_at" => "",
            "unloading_at" => "2026-10-01T10:00:00Z"
          }
        }
      })

    assert [%{loading_at: nil, unloading_at: ~U[2026-10-01 10:00:00Z]}] = updated.deliveries
  end

  test "配車の時間を縮めて既存の時刻が範囲外になるとエラー", %{scope: scope} do
    {:ok, dispatch} = create(scope, delivery(%{"unloading_at" => "2026-10-01T11:30:00Z"}))
    [d] = dispatch.deliveries

    assert {:error, changeset} =
             Dispatches.update_dispatch(scope, dispatch, %{
               "ended_at" => "2026-10-01T11:00:00Z",
               "deliveries" => %{
                 "0" => %{
                   "id" => d.id,
                   "destination" => "東京",
                   "unloading_at" => "2026-10-01T11:30:00Z"
                 }
               }
             })

    assert %{deliveries: [%{unloading_at: [_]}]} = errors_on(changeset)
  end

  test "配送ごとでも、コース一括でも入力できる（B-4）", %{scope: scope} do
    assert {:ok, %{deliveries: [d]}} =
             create(
               scope,
               delivery(%{"fare_yen" => "5000", "loading_at" => "2026-10-01T09:30:00Z"}),
               %{"pricing_type" => "per_delivery"}
             )

    assert d.fare_yen == 5000
    assert d.loading_at == ~U[2026-10-01 09:30:00Z]

    assert {:ok, %{deliveries: [d]}} =
             create(
               scope,
               delivery(%{"fare_yen" => "5000", "loading_at" => "2026-10-01T09:30:00Z"})
             )

    assert d.fare_yen == nil
    assert d.loading_at == ~U[2026-10-01 09:30:00Z]
  end

  test "CSVは配送先と同じ順に時刻を連結し、未入力は - にする（JST）", %{scope: scope} do
    {:ok, _} =
      create(scope, %{
        "0" => %{
          "destination" => "東京",
          "loading_at" => "2026-10-01T09:30:00Z",
          "unloading_at" => "2026-10-01T10:30:00Z"
        },
        "1" => %{"destination" => "横浜"}
      })

    {:ok, [row]} = Exports.stream_rows(scope, :dispatches, %{}, &Enum.to_list/1)

    assert row.destinations == "東京、横浜"
    assert row.loading_times == "10/01 18:30、-"
    assert row.unloading_times == "10/01 19:30、-"
  end
end
