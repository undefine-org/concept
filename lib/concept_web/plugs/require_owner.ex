defmodule ConceptWeb.Plugs.RequireOwner do
  @moduledoc """
  Plug that allows only workspace owners to access a route.

  - If no user is logged in → redirects to /sign-in.
  - If the user is an owner of at least one workspace → allows.
  - Otherwise → 403 Forbidden.
  """

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> redirect(to: "/sign-in")
        |> halt()

      user ->
        if owner?(user) do
          conn
        else
          conn
          |> put_status(:forbidden)
          |> put_resp_content_type("text/plain")
          |> send_resp(403, "Forbidden")
          |> halt()
        end
    end
  end

  defp owner?(user) do
    import Ash.Query

    case Concept.Accounts.Membership
         |> filter(user_id == ^user.id and role == :owner)
         |> limit(1)
         |> Ash.read(actor: user) do
      {:ok, [_ | _]} -> true
      _ -> false
    end
  end
end
