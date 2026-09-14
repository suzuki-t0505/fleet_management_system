defmodule CoreApp.AlertsTest do
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Alerts
  alias CoreApp.Alerts.AlertNotification
  alias CoreApp.Alerts.Deadline
  alias CoreApp.Utils.ConvertDatetime

  defp setup_offices(_context) do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    %{
      office_a: office_a,
      office_b: office_b,
      manager_a: manager_fixture(%{office_id: office_a.id}) |> Scope.for_user(),
      manager_b: manager_fixture(%{office_id: office_b.id}) |> Scope.for_user(),
      admin: admin_fixture(%{office_id: office_a.id}) |> Scope.for_user(),
      today: ConvertDatetime.today()
    }
  end

  defp in_days(today, days), do: today |> Date.add(days) |> Date.to_iso8601()

  describe "stage_for/1" do
    test "通知する残日数だけ段階を返す" do
      assert AlertNotification.stage_for(60) == :d60
      assert AlertNotification.stage_for(30) == :d30
      assert AlertNotification.stage_for(7) == :d7
      assert AlertNotification.stage_for(0) == :d0
      assert AlertNotification.stage_for(59) == nil
      assert AlertNotification.stage_for(31) == nil
    end

    test "超過は7日ごとに段階を返す" do
      assert AlertNotification.stage_for(-7) == :overdue
      assert AlertNotification.stage_for(-14) == :overdue
      assert AlertNotification.stage_for(-1) == nil
      assert AlertNotification.stage_for(-13) == nil
    end
  end

  describe "list_deadlines/2" do
    setup :setup_offices

    test "車両の5種類の期限を抽出する", %{manager_a: scope, today: today} do
      vehicle_fixture(scope, %{
        "inspection_expires_on" => in_days(today, 10),
        "liability_insurance_expires_on" => in_days(today, 20),
        "voluntary_insurance_expires_on" => in_days(today, 30),
        "next_periodic_3m_on" => in_days(today, 40),
        "next_periodic_12m_on" => in_days(today, 50)
      })

      types =
        scope |> Alerts.list_deadlines() |> Map.fetch!(:entries) |> Enum.map(& &1.alert_type)

      assert types == [
               :inspection,
               :liability_insurance,
               :voluntary_insurance,
               :periodic_3m,
               :periodic_12m
             ]
    end

    test "運転者の免許証有効期限を抽出する", %{manager_a: scope, today: today} do
      driver = driver_fixture(scope, %{"license_expires_on" => in_days(today, 5)})

      assert [deadline] = Alerts.list_deadlines(scope).entries
      assert deadline.target_type == :driver
      assert deadline.target_id == driver.id
      assert deadline.target_name == driver.name
      assert deadline.alert_type == :license
      assert deadline.days_left == 5
    end

    test "期限が遠いものは含まない", %{manager_a: scope, today: today} do
      vehicle_fixture(scope, %{"inspection_expires_on" => in_days(today, 61)})

      assert Alerts.list_deadlines(scope).entries == []
    end

    test "廃車と退職者は対象外", %{manager_a: scope, today: today} do
      vehicle_fixture(scope, %{
        "status" => "scrapped",
        "inspection_expires_on" => in_days(today, 3)
      })

      driver_fixture(scope, %{
        "employment_type" => "retired",
        "retired_on" => in_days(today, -1),
        "license_expires_on" => in_days(today, 3)
      })

      assert Alerts.list_deadlines(scope).entries == []
    end

    test "残日数の昇順で返す", %{manager_a: scope, today: today} do
      vehicle_fixture(scope, %{
        "plate_number" => "品川100あ1",
        "inspection_expires_on" => in_days(today, 40)
      })

      vehicle_fixture(scope, %{
        "plate_number" => "品川100あ2",
        "inspection_expires_on" => in_days(today, -3)
      })

      assert [first, second] = Alerts.list_deadlines(scope).entries
      assert first.days_left == -3
      assert second.days_left == 40
    end

    test "他拠点の期限は見えない", %{manager_a: scope, manager_b: other, today: today} do
      vehicle_fixture(other, %{"inspection_expires_on" => in_days(today, 3)})

      assert Alerts.list_deadlines(scope).entries == []
    end

    test "管理者は全拠点を見られ、拠点で絞り込める", %{
      admin: admin,
      manager_a: manager_a,
      manager_b: manager_b,
      office_b: office_b,
      today: today
    } do
      vehicle_fixture(manager_a, %{"inspection_expires_on" => in_days(today, 3)})
      vehicle_fixture(manager_b, %{"inspection_expires_on" => in_days(today, 4)})

      assert Alerts.list_deadlines(admin).total_entries == 2

      assert [deadline] =
               Alerts.list_deadlines(admin, %{"office_id" => office_b.id}).entries

      assert deadline.office_name == office_b.name
    end

    test "残日数・期限種別・キーワードで絞り込める", %{manager_a: scope, today: today} do
      vehicle_fixture(scope, %{
        "plate_number" => "品川100あ11",
        "inspection_expires_on" => in_days(today, -2)
      })

      vehicle_fixture(scope, %{
        "plate_number" => "練馬500さ22",
        "inspection_expires_on" => in_days(today, 45),
        "next_periodic_3m_on" => in_days(today, 5)
      })

      assert [overdue] = Alerts.list_deadlines(scope, %{"within" => "overdue"}).entries
      assert overdue.days_left == -2

      assert Alerts.list_deadlines(scope, %{"within" => "7"}).total_entries == 2

      assert [periodic] =
               Alerts.list_deadlines(scope, %{"alert_type" => "periodic_3m"}).entries

      assert periodic.alert_type == :periodic_3m

      assert Alerts.list_deadlines(scope, %{"q" => "練馬"}).total_entries == 2
    end
  end

  describe "count_deadlines_by_urgency/1" do
    setup :setup_offices

    test "超過と30日以内を数える", %{manager_a: scope, today: today} do
      vehicle_fixture(scope, %{"inspection_expires_on" => in_days(today, -1)})
      vehicle_fixture(scope, %{"inspection_expires_on" => in_days(today, 10)})
      vehicle_fixture(scope, %{"inspection_expires_on" => in_days(today, 45)})

      assert Alerts.count_deadlines_by_urgency(scope) == %{overdue: 1, within_30: 1}
    end
  end

  describe "all_notifiable_deadlines/1" do
    setup :setup_offices

    test "通知する段階に当たるものだけを返す", %{manager_a: scope, today: today} do
      vehicle_fixture(scope, %{
        "plate_number" => "品川100あ30",
        "inspection_expires_on" => in_days(today, 30)
      })

      vehicle_fixture(scope, %{
        "plate_number" => "品川100あ29",
        "inspection_expires_on" => in_days(today, 29)
      })

      assert [deadline] = Alerts.all_notifiable_deadlines(today)
      assert deadline.days_left == 30
      assert Alerts.notify_stage(deadline) == :d30
    end

    test "拠点をまたいで走査する", %{manager_a: manager_a, manager_b: manager_b, today: today} do
      vehicle_fixture(manager_a, %{"inspection_expires_on" => in_days(today, 7)})
      vehicle_fixture(manager_b, %{"inspection_expires_on" => in_days(today, 7)})

      assert length(Alerts.all_notifiable_deadlines(today)) == 2
    end
  end

  describe "通知ログ" do
    setup :setup_offices

    setup %{manager_a: scope, today: today} do
      vehicle = vehicle_fixture(scope, %{"inspection_expires_on" => in_days(today, 7)})

      %{deadline: hd(Alerts.list_deadlines(scope).entries), vehicle: vehicle}
    end

    test "送信を記録すると送信済みになる", %{deadline: deadline, today: today} do
      refute Alerts.notified?(deadline, :d7, today)

      assert {:ok, notification} = Alerts.record_sent(deadline, :d7, today)
      assert notification.status == :sent
      assert notification.notified_on == today
      assert Alerts.notified?(deadline, :d7, today)
    end

    test "同じ段階を2回記録しても行が増えない", %{deadline: deadline, today: today} do
      {:ok, _} = Alerts.record_sent(deadline, :d7, today)
      {:ok, _} = Alerts.record_sent(deadline, :d7, today)

      assert length(Alerts.all_notifications_for(:vehicle, deadline.target_id)) == 1
    end

    test "失敗は送信済みとみなさない", %{deadline: deadline, today: today} do
      {:ok, notification} = Alerts.record_failed(deadline, :d7, "接続できません", today)

      assert notification.status == :failed
      assert notification.error_message == "接続できません"
      refute Alerts.notified?(deadline, :d7, today)
    end

    test "超過は7日経つと再び通知対象になる", %{deadline: %Deadline{} = deadline, today: today} do
      overdue = %Deadline{deadline | days_left: -7}

      {:ok, _} = Alerts.record_sent(overdue, :overdue, today)

      assert Alerts.notified?(overdue, :overdue, today)
      assert Alerts.notified?(overdue, :overdue, Date.add(today, 6))
      refute Alerts.notified?(overdue, :overdue, Date.add(today, 7))
    end
  end
end
