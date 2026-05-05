defmodule ConceptWeb.Router do
  use ConceptWeb, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ConceptWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  pipeline :require_owner do
    plug ConceptWeb.Plugs.RequireOwner
  end

  scope "/", ConceptWeb do
    pipe_through :browser

    ash_authentication_live_session :public_routes,
      on_mount: [{ConceptWeb.LiveUserAuth, :live_user_optional}] do
      live "/", HomeLive, :index
    end

    ash_authentication_live_session :authenticated_routes,
      on_mount: [{ConceptWeb.LiveUserAuth, :live_user_required}] do
      live "/w", WorkspaceLive, :index
      live "/w/:workspace_slug", WorkspaceLive, :workspace
      live "/w/:workspace_slug/p/:page_id", WorkspaceLive, :page
    end
  end

  scope "/", ConceptWeb do
    pipe_through :browser

    auth_routes AuthController, Concept.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{ConceptWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    ConceptWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  ConceptWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route Concept.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [ConceptWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(Concept.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [ConceptWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI]
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", ConceptWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:concept, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ConceptWeb.Telemetry
    end
  end

  import AshAdmin.Router

    scope "/admin" do
      pipe_through [:browser, :require_owner]

      ash_admin "/"
      # arcana_dashboard "/arcana"
    end
end
