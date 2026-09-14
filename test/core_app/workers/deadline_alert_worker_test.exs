defmodule CoreApp.Workers.DeadlineAlertWorkerTest do
  use CoreApp.DataCase, async: true
  use Oban.Testing, repo: CoreApp.Repo

  import CoreApp.AccountsFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Alerts
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Workers.AlertMailWorker
  alias CoreApp.Workers.DeadlineAlertWorker

  setup do
    office = office_fixture()

    %{
      office: office,
      scope: manager_fixture(%{office_id: office.id}) |> Scope.for_user(),
      today: ConvertDatetime.today()
    }
  end

  defp in_days(today, days), do: today |> Date.add(days) |> Date.to_iso8601()

  test "通知対象を送信ジョブとしてエンキューする", %{scope: scope, today: today} do
    vehicle = vehicle_fixture(scope, %{"inspection_expires_on" => in_days(today, 30)})

    assert {:ok, 1} = perform_job(DeadlineAlertWorker, %{})

    assert_enqueued(worker: AlertMailWorker, queue: :mailers)

    assert [job] = all_enqueued(worker: AlertMailWorker)
    assert job.args["target_id"] == vehicle.id
    assert job.args["alert_type"] == "inspection"
    assert job.args["notify_stage"] == "d30"
    assert job.args["notified_on"] == Date.to_iso8601(today)
  end

  test "通知しない残日数はエンキューしない", %{scope: scope, today: today} do
    vehicle_fixture(scope, %{"inspection_expires_on" => in_days(today, 29)})

    assert {:ok, 0} = perform_job(DeadlineAlertWorker, %{})
    refute_enqueued(worker: AlertMailWorker)
  end

  test "同じ日に2回実行しても送信ジョブは1件しか増えない", %{scope: scope, today: today} do
    vehicle_fixture(scope, %{"inspection_expires_on" => in_days(today, 7)})

    {:ok, 1} = perform_job(DeadlineAlertWorker, %{})
    {:ok, _count} = perform_job(DeadlineAlertWorker, %{})

    assert length(all_enqueued(worker: AlertMailWorker)) == 1
  end

  test "送信済みの段階はエンキューしない", %{scope: scope, today: today} do
    vehicle_fixture(scope, %{"inspection_expires_on" => in_days(today, 7)})
    deadline = hd(Alerts.list_deadlines(scope).entries)
    {:ok, _notification} = Alerts.record_sent(deadline, :d7, today)

    assert {:ok, 0} = perform_job(DeadlineAlertWorker, %{})
    refute_enqueued(worker: AlertMailWorker)
  end

  test "超過は7日ごとにだけエンキューする", %{scope: scope, today: today} do
    vehicle_fixture(scope, %{
      "plate_number" => "品川100あ7",
      "inspection_expires_on" => in_days(today, -7)
    })

    vehicle_fixture(scope, %{
      "plate_number" => "品川100あ3",
      "inspection_expires_on" => in_days(today, -3)
    })

    assert {:ok, 1} = perform_job(DeadlineAlertWorker, %{})

    assert [job] = all_enqueued(worker: AlertMailWorker)
    assert job.args["notify_stage"] == "overdue"
    assert job.args["target_name"] == "品川100あ7"
  end

  test "廃車と退職者はエンキューしない", %{scope: scope, today: today} do
    vehicle_fixture(scope, %{
      "status" => "scrapped",
      "inspection_expires_on" => in_days(today, 7)
    })

    driver_fixture(scope, %{
      "employment_type" => "retired",
      "retired_on" => in_days(today, -1),
      "license_expires_on" => in_days(today, 7)
    })

    assert {:ok, 0} = perform_job(DeadlineAlertWorker, %{})
  end

  test "運転者の免許証期限もエンキューする", %{scope: scope, today: today} do
    driver = driver_fixture(scope, %{"license_expires_on" => in_days(today, 60)})

    assert {:ok, 1} = perform_job(DeadlineAlertWorker, %{})

    assert [job] = all_enqueued(worker: AlertMailWorker)
    assert job.args["target_type"] == "driver"
    assert job.args["target_id"] == driver.id
    assert job.args["notify_stage"] == "d60"
  end
end
