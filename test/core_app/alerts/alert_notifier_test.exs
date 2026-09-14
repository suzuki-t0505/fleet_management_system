defmodule CoreApp.Alerts.AlertNotifierTest do
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import Swoosh.TestAssertions

  alias CoreApp.Alerts.AlertNotifier
  alias CoreApp.Alerts.Deadline

  defp flush_emails do
    receive do
      {:email, _email} -> flush_emails()
    after
      0 -> :ok
    end
  end

  defp deadline(attrs) do
    Map.merge(
      %Deadline{
        target_type: :driver,
        target_id: "01J0000000000000000000000A",
        target_name: "運転 太郎",
        office_id: "01J0000000000000000000000B",
        office_name: "A営業所",
        alert_type: :license,
        deadline_on: ~D[2026-10-01],
        days_left: 30
      },
      attrs
    )
  end

  test "期限アラートの本文に対象・期限日・残日数・URLを載せる" do
    admin = admin_fixture()
    flush_emails()

    assert {:ok, _email} = AlertNotifier.deliver_deadline_alert([admin], deadline(%{}))

    assert_email_sent(fn email ->
      assert email.subject == "[車両管理] A営業所 運転 太郎 の免許証有効期限が残り30日です"
      assert email.text_body =~ "対象: 運転 太郎（A営業所）"
      assert email.text_body =~ "期限日: 2026-10-01"
      assert email.text_body =~ "残日数: あと30日"
      assert email.text_body =~ "/management/drivers/01J0000000000000000000000A"
    end)
  end

  test "超過は超過日数を載せる" do
    admin = admin_fixture()
    flush_emails()

    {:ok, _email} = AlertNotifier.deliver_deadline_alert([admin], deadline(%{days_left: -14}))

    assert_email_sent(fn email ->
      assert email.subject =~ "[車両管理][超過]"
      assert email.text_body =~ "残日数: 14日超過"
    end)
  end

  test "通知先がいない場合は送らない" do
    assert AlertNotifier.deliver_deadline_alert([], deadline(%{})) == {:error, :no_recipients}
    assert AlertNotifier.deliver_job_failure([], "boom") == {:error, :no_recipients}
  end

  test "ジョブの異常終了を管理者に通知する" do
    admin = admin_fixture()
    flush_emails()

    assert {:ok, _email} = AlertNotifier.deliver_job_failure([admin], "接続できません")

    assert_email_sent(fn email ->
      assert email.subject == "[車両管理] 期限アラートの定時処理が失敗しました"
      assert email.text_body =~ "接続できません"
    end)
  end
end
