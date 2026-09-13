defmodule CoreAppWeb.Router do
  use CoreAppWeb, :router

  import CoreAppWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CoreAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  ## 一般利用者向け

  scope "/", CoreAppWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{CoreAppWeb.UserAuth, :require_authenticated}] do
      live "/", DashboardLive.Index, :index

      scope "/vehicles", VehicleLive.Member do
        live "/", Index, :index
        live "/:id", Show, :show
      end

      scope "/operation_reports", OperationReportLive.Member do
        live "/", Index, :index
        live "/new", Form, :new
        live "/:id/edit", Form, :edit
        live "/:id", Show, :show
      end

      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  ## 運行管理者・管理者向け

  scope "/management", CoreAppWeb do
    pipe_through [:browser, :require_manager_user]

    live_session :require_manager,
      on_mount: [{CoreAppWeb.UserAuth, :require_manager}] do
      scope "/vehicles", VehicleLive.Manager do
        live "/", Index, :index
        live "/new", Form, :new
        live "/:id/edit", Form, :edit
        live "/:id", Show, :show
      end

      scope "/drivers", DriverLive.Manager do
        live "/", Index, :index
        live "/new", Form, :new
        live "/:id/edit", Form, :edit
        live "/:id", Show, :show
      end

      scope "/operation_reports", OperationReportLive.Manager do
        live "/", Index, :index
        live "/:id/edit", Form, :edit
        live "/:id", Show, :show
      end

      scope "/maintenances", MaintenanceLive.Manager do
        live "/", Index, :index
        live "/new", Form, :new
        live "/:id/edit", Form, :edit
        live "/:id", Show, :show
      end

      live "/alerts", AlertLive.Manager.Index, :index

      # 事故ヒヤリ・集計の各画面は機能実装時に追加する
    end
  end

  ## 管理者向け

  scope "/management", CoreAppWeb do
    pipe_through [:browser, :require_admin_user]

    live_session :require_admin,
      on_mount: [{CoreAppWeb.UserAuth, :require_admin}] do
      # ユーザー・拠点・監査ログの各画面は機能実装時に追加する
    end
  end

  ## 認証系

  scope "/", CoreAppWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{CoreAppWeb.UserAuth, :mount_current_scope}] do
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:core_app, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CoreAppWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
