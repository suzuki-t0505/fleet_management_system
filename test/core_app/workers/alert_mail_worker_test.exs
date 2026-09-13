defmodule CoreApp.Workers.AlertMailWorkerTest do
  use CoreApp.DataCase, async: true
  use Oban.Testing, repo: CoreApp.Repo

  import CoreApp.AccountsFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.VehiclesFixtures
  import Swoosh.TestAssertions

  alias CoreApp.Accounts
  alias CoreApp.Accounts.Scope
  alias CoreApp.Alerts
  alias CoreApp.Alerts.Deadline
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Workers.AlertMailWorker

  setup do
    office = office_fixture(%{"name" => "A営業所"})
    manager = manager_fixture(%{office_id: office.id})
    scope = Scope.for_user(manager)
    today = ConvertDatetime.today()

    vehicle_fixture(scope, %{
      "plate_number" => "品川100あ55",
      "inspection_expires_on" => today |> Date.add(7) |> Date.to_iso8601()
    })

    # 利用者の作成時に送られる確認メールを片付け、アラートのメールだけを検証する
    flush_emails()

    %{
      office: office,
      manager: manager,
      scope: scope,
      today: today,
      deadline: hd(Alerts.list_deadlines(scope).entries)
    }
  end

  defp flush_emails do
    receive do
      {:email, _email} -> flush_emails()
    after
      0 -> :ok
    end
  end

  defp args(deadline, stage, today) do
    deadline
    |> Deadline.to_args()
    |> Map.merge(%{
      "notify_stage" => to_string(stage),
      "notified_on" => Date.to_iso8601(today)
    })
  end

  test "メールを送り、送信済みとして記録する", %{deadline: deadline, today: today} do
    assert :ok = perform_job(AlertMailWorker, args(deadline, :d7, today))

    assert_email_sent(subject: "[車両管理] A営業所 品川100あ55 の車検満了日が残り7日です")
    assert Alerts.notified?(deadline, :d7, today)

    assert [notification] = Alerts.all_notifications_for(:vehicle, deadline.target_id)
    assert notification.status == :sent
    assert notification.sent_at
  end

  test "宛先は対象拠点の運行管理者と全管理者", %{deadline: deadline, manager: manager, today: today} do
    admin = admin_fixture()
    other_office = office_fixture()
    other_manager = manager_fixture(%{office_id: other_office.id})
    flush_emails()

    :ok = perform_job(AlertMailWorker, args(deadline, :d7, today))

    assert_email_sent(fn email ->
      addresses = Enum.map(email.to, fn {_name, address} -> address end)

      refute other_manager.email in addresses
      assert Enum.sort(addresses) == Enum.sort([manager.email, admin.email])
    end)
  end

  test "送信済みの段階は再送しない", %{deadline: deadline, today: today} do
    {:ok, _notification} = Alerts.record_sent(deadline, :d7, today)

    assert :ok = perform_job(AlertMailWorker, args(deadline, :d7, today))

    refute_email_sent()
  end

  test "通知先がいない場合は失敗として記録し打ち切る", %{deadline: deadline, manager: manager, today: today} do
    {:ok, _user} = Accounts.update_user_profile(manager, %{active: false})

    assert {:cancel, :no_recipients} = perform_job(AlertMailWorker, args(deadline, :d7, today))

    assert [notification] = Alerts.all_notifications_for(:vehicle, deadline.target_id)
    assert notification.status == :failed
    assert notification.error_message == "通知先の利用者が存在しません"
    refute Alerts.notified?(deadline, :d7, today)
  end

  test "超過の件名は期限切れであることを示す", %{deadline: %Deadline{} = deadline, today: today} do
    overdue = %Deadline{deadline | days_left: -7, deadline_on: Date.add(today, -7)}

    assert :ok = perform_job(AlertMailWorker, args(overdue, :overdue, today))

    assert_email_sent(subject: "[車両管理][超過] A営業所 品川100あ55 の車検満了日が期限切れです")
  end
end
