defmodule ConceptWeb.Controllers.AuthControllerTest do
  use ConceptWeb.ConnCase, async: true

  describe "auth pages render with Notion-style classes" do
    test "GET /sign-in renders with ora-auth-root class", %{conn: conn} do
      response = get(conn, ~p"/sign-in")
      assert response.resp_body =~ "ora-auth-root"
    end

    test "GET /register renders with ora-auth-root class", %{conn: conn} do
      response = get(conn, ~p"/register")
      assert response.resp_body =~ "ora-auth-root"
    end

    test "GET /reset renders with ora-auth-root class", %{conn: conn} do
      response = get(conn, ~p"/reset")
      assert response.resp_body =~ "ora-auth-root"
    end
  end
end
