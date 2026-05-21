defmodule ConceptWeb.AiBlockRenderTest do
  use ConceptWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Concept.Accounts
  alias Concept.Pages
  alias Concept.Knowledge
  alias Concept.Repo
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "aiblock#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    # Confirm user
    Repo.update_all(
      from(u in Concept.Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: DateTime.utc_now()]
    )

    # Sign in
    {:ok, signed_in} =
      Concept.Accounts.User
      |> Ash.Query.for_read(:sign_in_with_password, %{email: user.email, password: "passw0rd!"})
      |> Ash.read_one(authorize?: false)

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session("user_token", signed_in.__metadata__.token)

    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)
    {:ok, page} = Pages.create_page("AI Test Page", ws.id, nil, actor: user, tenant: ws.id)

    {:ok, conn: conn, user: user, ws: ws, page: page}
  end

  describe "empty AI block" do
    test "renders with state=empty", %{conn: conn, user: user, ws: ws, page: page} do
      # Create empty AI answer block
      {:ok, block} =
        Pages.create_block(page.id, :ai_answer, ws.id, nil,
          actor: user,
          tenant: ws.id
        )

      {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

      # Wrapper carries the LiveComponent wiring; the Lit element is its child.
      assert has_element?(view, "div#ai-#{block.id}[phx-hook=\"OraBlock\"]")
      assert has_element?(view, "div#ai-#{block.id}[data-events=\"evaluate refresh retry\"]")
      assert has_element?(view, "ora-ai-block#ora-ai-#{block.id}[state=\"empty\"]")
    end
  end

  describe "answered AI block" do
    test "renders with state=answered and preview content", %{
      conn: conn,
      user: user,
      ws: ws,
      page: page
    } do
      # Create AI answer block
      {:ok, block} =
        Pages.create_block(page.id, :ai_answer, ws.id, nil,
          actor: user,
          tenant: ws.id
        )

      # Create a conversation and completed message
      {:ok, conversation} =
        Knowledge.Chat.create_conversation(
          %{title: "Test Conversation"},
          actor: user,
          authorize?: false
        )

      # Create user message
      user_message =
        Concept.Knowledge.Chat.Message
        |> Ash.Changeset.for_create(:create, %{text: "Test question"}, actor: user)
        |> Ash.Changeset.set_argument(:conversation_id, conversation.id)
        |> Ash.create!(actor: user, authorize?: false)

      # Create completed assistant response
      system_actor = %{system?: true}

      {:ok, assistant_message} =
        Concept.Knowledge.Chat.Message
        |> Ash.Changeset.for_create(:upsert_response, %{
          id: Ash.UUIDv7.generate(),
          conversation_id: conversation.id,
          response_to_id: user_message.id,
          text: "This is the AI answer.",
          complete: true
        })
        |> Ash.create(actor: system_actor, authorize?: false)

      # Update block content to point to the message (using system actor to bypass lock)
      _updated_block =
        block
        |> Ash.Changeset.for_update(
          :update_content,
          %{
            content: %{
              "message_id" => assistant_message.id,
              "model" => "default",
              "ran_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          },
          actor: %{system?: true}
        )
        |> Ash.update!(actor: %{system?: true}, tenant: ws.id)

      {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

      assert has_element?(view, "div#ai-#{block.id}[phx-hook=\"OraBlock\"]")
      assert has_element?(view, "ora-ai-block#ora-ai-#{block.id}[state=\"answered\"]")

      assert has_element?(
               view,
               "ora-ai-block#ora-ai-#{block.id}[message-id=\"#{assistant_message.id}\"]"
             )
    end
  end

  describe "streaming AI block" do
    test "renders with state=streaming for incomplete message", %{
      conn: conn,
      user: user,
      ws: ws,
      page: page
    } do
      # Create AI answer block
      {:ok, block} =
        Pages.create_block(page.id, :ai_answer, ws.id, nil,
          actor: user,
          tenant: ws.id
        )

      # Create a conversation
      {:ok, conversation} =
        Knowledge.Chat.create_conversation(
          %{title: "Test Conversation"},
          actor: user,
          authorize?: false
        )

      # Create user message
      user_message =
        Concept.Knowledge.Chat.Message
        |> Ash.Changeset.for_create(:create, %{text: "Test question"}, actor: user)
        |> Ash.Changeset.set_argument(:conversation_id, conversation.id)
        |> Ash.create!(actor: user, authorize?: false)

      # Create incomplete assistant response (streaming)
      system_actor = %{system?: true}

      {:ok, streaming_message} =
        Concept.Knowledge.Chat.Message
        |> Ash.Changeset.for_create(:upsert_response, %{
          id: Ash.UUIDv7.generate(),
          conversation_id: conversation.id,
          response_to_id: user_message.id,
          text: "Partial answer...",
          complete: false
        })
        |> Ash.create(actor: system_actor, authorize?: false)

      # Update block content to point to the streaming message (using system actor to bypass lock)
      _updated_block =
        block
        |> Ash.Changeset.for_update(
          :update_content,
          %{
            content: %{
              "message_id" => streaming_message.id,
              "model" => "default",
              "ran_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          },
          actor: %{system?: true}
        )
        |> Ash.update!(actor: %{system?: true}, tenant: ws.id)

      {:ok, view, _html} = live(conn, ~p"/w/#{ws.slug}/p/#{page.id}")

      assert has_element?(view, "ora-ai-block#ora-ai-#{block.id}[state=\"streaming\"]")
    end
  end
end
