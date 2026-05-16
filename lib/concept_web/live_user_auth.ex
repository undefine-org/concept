defmodule ConceptWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.

  Extends the `:current_user` assign (set by AshAuthentication) with a
  `:current_scope` assign that bundles the authenticated `user` with an
  optional `workspace` + `role` resolved from route params.

  `current_scope` is a `Concept.Accounts.Scope` struct (or nil for
  unauthenticated contexts). Use it in layouts, components, and
  Ash policy checks instead of ad-hoc `@current_user` / `@workspace` reads.
  """

  import Phoenix.Component
  use ConceptWeb, :verified_routes

  alias Concept.Accounts.Scope

  # ── Plumbing helper ──────────────────────────────────────────────

  @doc false
  def compute_scope(nil, _params, _socket), do: nil

  def compute_scope(user, params, _socket) do
    workspace_id = resolve_workspace_id(params, user)
    Scope.for_user(user, workspace_id)
  end

  defp resolve_workspace_id(params, user) do
    case params["workspace_slug"] do
      nil -> nil
      slug -> resolve_slug_to_id(slug, user)
    end
  end

  defp resolve_slug_to_id(slug, user) do
    case Concept.Accounts.Workspace.by_slug(slug, actor: user) do
      {:ok, %{id: id}} -> id
      _ -> nil
    end
  end

  # ── on_mount hooks ───────────────────────────────────────────────

  # This is used for nested liveviews to fetch the current user.
  # To use, place the following at the top of that liveview:
  # on_mount {ConceptWeb.LiveUserAuth, :current_user}
  def on_mount(:current_user, _params, session, socket) do
    {:cont, AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session)}
  end

  def on_mount(:live_user_optional, params, _session, socket) do
    socket =
      if socket.assigns[:current_user] do
        socket
      else
        assign(socket, :current_user, nil)
      end

    scope = compute_scope(socket.assigns[:current_user], params, socket)
    {:cont, assign(socket, :current_scope, scope)}
  end

  def on_mount(:live_user_required, params, _session, socket) do
    if socket.assigns[:current_user] do
      scope = compute_scope(socket.assigns[:current_user], params, socket)
      {:cont, assign(socket, :current_scope, scope)}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_no_user, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, assign(socket, current_user: nil, current_scope: nil)}
    end
  end

  # Runs on auth routes (sign_in / confirm / magic_sign_in). When a session
  # already carries a signed-in user, jump straight to their primary
  # workspace so we never strand them on /sign-in or /.
  def on_mount(:after_sign_in, _params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:cont, socket}

      user ->
        case Concept.Accounts.get_primary_workspace(user, actor: user) do
          {:ok, %{slug: slug}} ->
            {:halt, Phoenix.LiveView.push_navigate(socket, to: ~p"/w/#{slug}")}

          _ ->
            {:cont, socket}
        end
    end
  end
end
