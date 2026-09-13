defmodule CoreApp.Utils.PaginationTest do
  use CoreApp.DataCase, async: true

  import CoreApp.OfficesFixtures
  import Ecto.Query

  alias CoreApp.Offices.Office
  alias CoreApp.Utils.Pagination

  defp query, do: from(o in Office, order_by: [asc: o.code])

  defp create_offices(count) do
    for i <- 1..count do
      office_fixture(%{"code" => "OF#{String.pad_leading(to_string(i), 4, "0")}"})
    end
  end

  describe "paginate/3" do
    test "既定は1ページ50件" do
      create_offices(51)

      page = Pagination.paginate(query(), %{}, Repo)

      assert length(page.entries) == 50
      assert page.page_number == 1
      assert page.page_size == 50
      assert page.total_entries == 51
      assert page.total_pages == 2
    end

    test "2ページ目は残りを返す" do
      create_offices(51)

      page = Pagination.paginate(query(), %{"page" => "2"}, Repo)

      assert length(page.entries) == 1
      assert page.page_number == 2
    end

    test "page_size を指定できる" do
      create_offices(5)

      page = Pagination.paginate(query(), %{"page_size" => "2"}, Repo)

      assert length(page.entries) == 2
      assert page.total_pages == 3
    end

    test "page_size の上限は100" do
      page = Pagination.paginate(query(), %{"page_size" => "1000"}, Repo)

      assert page.page_size == 100
    end

    test "範囲外のページ番号は最後のページに丸める" do
      create_offices(3)

      page = Pagination.paginate(query(), %{"page" => "99"}, Repo)

      assert page.page_number == 1
      assert length(page.entries) == 3
    end

    test "不正なページ番号は1として扱う" do
      create_offices(1)

      assert Pagination.paginate(query(), %{"page" => "abc"}, Repo).page_number == 1
      assert Pagination.paginate(query(), %{"page" => "-5"}, Repo).page_number == 1
    end

    test "0件でも total_pages は1" do
      page = Pagination.paginate(query(), %{}, Repo)

      assert page.entries == []
      assert page.total_entries == 0
      assert page.total_pages == 1
    end
  end

  describe "previous_page?/1 と next_page?/1" do
    test "ページの前後を判定する" do
      create_offices(51)

      first = Pagination.paginate(query(), %{"page" => "1"}, Repo)
      last = Pagination.paginate(query(), %{"page" => "2"}, Repo)

      refute Pagination.previous_page?(first)
      assert Pagination.next_page?(first)
      assert Pagination.previous_page?(last)
      refute Pagination.next_page?(last)
    end
  end

  describe "range/1" do
    test "表示している範囲を返す" do
      create_offices(51)

      assert Pagination.range(Pagination.paginate(query(), %{"page" => "1"}, Repo)) == {1, 50}
      assert Pagination.range(Pagination.paginate(query(), %{"page" => "2"}, Repo)) == {51, 51}
    end

    test "0件のときは {0, 0}" do
      assert Pagination.range(Pagination.paginate(query(), %{}, Repo)) == {0, 0}
    end
  end
end
