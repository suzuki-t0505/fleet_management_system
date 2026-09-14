defmodule CoreApp.AttachmentsTest do
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.AttachmentsFixtures
  import CoreApp.IncidentsFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Attachments
  alias CoreApp.Attachments.Attachment

  setup do
    office = office_fixture()
    scope = manager_fixture(%{office_id: office.id}) |> Scope.for_user()
    vehicle = vehicle_fixture(scope)
    incident = incident_fixture(scope, vehicle)

    %{scope: scope, incident: incident, target: {:incident, incident.id}}
  end

  describe "create_attachment/3" do
    test "画像を保存し、内容を読み出せる", %{scope: scope, target: target} do
      path = png_path("これは写真です")

      assert {:ok, %Attachment{} = attachment} =
               Attachments.create_attachment(scope, target, %{
                 path: path,
                 filename: "現場写真.png",
                 byte_size: File.stat!(path).size
               })

      assert attachment.content_type == "image/png"
      assert attachment.filename == "現場写真.png"
      assert attachment.uploaded_by_user_id == scope.user.id
      assert attachment.storage_key =~ "attachments/incident/"

      assert {:ok, binary} = Attachments.read_attachment(attachment)
      assert binary =~ "これは写真です"
    end

    test "PDF と JPEG も受け入れる", %{scope: scope, target: target} do
      for {path, expected} <- [{pdf_path(), "application/pdf"}, {jpeg_path(), "image/jpeg"}] do
        assert {:ok, attachment} =
                 Attachments.create_attachment(scope, target, %{
                   path: path,
                   filename: Path.basename(path),
                   byte_size: File.stat!(path).size
                 })

        assert attachment.content_type == expected
      end
    end

    test "拡張子を偽装したファイルは受け付けない", %{scope: scope, target: target} do
      path = disguised_path()

      assert Attachments.create_attachment(scope, target, %{
               path: path,
               filename: "偽装.png",
               byte_size: File.stat!(path).size
             }) == {:error, :unsupported_type}

      assert Attachments.all_attachments_for(:incident, elem(target, 1)) == []
    end

    test "V-28 10MBを超えるファイルは受け付けない", %{scope: scope, target: target} do
      path = png_path()

      assert Attachments.create_attachment(scope, target, %{
               path: path,
               filename: "大きい写真.png",
               byte_size: Attachments.max_bytes() + 1
             }) == {:error, :too_large}
    end

    test "V-28 1記録につき10件までしか添付できない", %{scope: scope, target: target} do
      for _index <- 1..Attachments.max_files() do
        attachment_fixture(scope, target)
      end

      path = png_path()

      assert Attachments.create_attachment(scope, target, %{
               path: path,
               filename: "11枚目.png",
               byte_size: File.stat!(path).size
             }) == {:error, :too_many_files}

      assert Attachments.count_attachments_for(:incident, elem(target, 1)) ==
               Attachments.max_files()
    end
  end

  describe "all_attachments_for/2" do
    test "対象に紐づくものだけを古い順に返す", %{scope: scope, incident: incident, target: target} do
      first = attachment_fixture(scope, target, %{filename: "1枚目.png"})
      second = attachment_fixture(scope, target, %{filename: "2枚目.png"})
      _other = attachment_fixture(scope, {:vehicle, incident.vehicle_id})

      ids = :incident |> Attachments.all_attachments_for(incident.id) |> Enum.map(& &1.id)

      assert ids == [first.id, second.id]
    end
  end

  describe "delete_attachment/2" do
    test "レコードを削除する", %{scope: scope, incident: incident, target: target} do
      attachment = attachment_fixture(scope, target)

      assert {:ok, _deleted} = Attachments.delete_attachment(scope, attachment)
      assert Attachments.all_attachments_for(:incident, incident.id) == []
    end
  end

  describe "content_type_of/1" do
    test "先頭バイトから形式を判定する" do
      assert Attachment.content_type_of("%PDF-1.7") == {:ok, "application/pdf"}
      assert Attachment.content_type_of(<<137, 80, 78, 71, 13, 10, 26, 10>>) == {:ok, "image/png"}
      assert Attachment.content_type_of(<<255, 216, 255, 0>>) == {:ok, "image/jpeg"}
      assert Attachment.content_type_of("plain text") == :error
    end
  end
end
