defmodule CoreAppWeb.PageController do
  use CoreAppWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
