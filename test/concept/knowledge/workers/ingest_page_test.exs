defmodule Concept.Knowledge.Workers.IngestPageTest do
  @moduledoc """
  BUG-049 — IngestPage worker must call `Pages.list_for_page/2` with a
  positional `page_id`, not a keyword list. Previously the call was
  `list_for_page(page_id: page_id, actor: actor, tenant: workspace_id)`,
  which made every ingestion fail with
  `Ash.Error.Query.InvalidArgument{field: :page_id, …}` and dead-lettered
  every Oban job.

  Also asserts the worker hands the loaded page + blocks to `Arcana.ingest/2`
  via the per-call `:chunker` override (`{BlockChunker, opts}`) so the custom
  `Concept.Knowledge.BlockChunker` can build chunks deterministically.
  """
  use Concept.DataCase, async: false

  alias Concept.{Accounts, Pages}
  alias Concept.Knowledge.Workers.IngestPage

  require Ash.Query

  defp fixtures do
    {:ok, user} =
      Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ingest_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [workspace]} = Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, page} =
      Pages.create_page("Ingest page", workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    {:ok, _block} =
      Pages.create_block(:page, page.id, :paragraph, workspace.id, nil,
        actor: user,
        tenant: workspace.id
      )

    %{user: user, workspace: workspace, page: page}
  end

  describe "perform/1 upsert" do
    setup do
      Application.put_env(:concept, :arcana_module, IngestPageTest.MockArcana)
      on_exit(fn -> Application.delete_env(:concept, :arcana_module) end)
      IngestPageTest.MockArcana.subscribe(self())
      :ok
    end

    test "succeeds for a real workspace/page (no InvalidArgument on list_for_page)" do
      %{workspace: ws, page: page} = fixtures()

      job = %Oban.Job{
        args: %{
          "workspace_id" => ws.id,
          "page_id" => page.id,
          "op" => "upsert"
        }
      }

      assert :ok = IngestPage.perform(job)
    end

    test "passes the loaded page + blocks to Arcana via the chunker override" do
      %{workspace: ws, page: page} = fixtures()

      job = %Oban.Job{
        args: %{
          "workspace_id" => ws.id,
          "page_id" => page.id,
          "op" => "upsert"
        }
      }

      assert :ok = IngestPage.perform(job)

      assert_receive {:ingest_called, _text, opts}, 500
      # Chunker inputs ride on the per-call `:chunker` override
      # (`{BlockChunker, opts}`), which Arcana threads to the chunker. A bare
      # `:chunker_opts` key is silently dropped by `Arcana.Ingest.ingest/2`.
      {Concept.Knowledge.BlockChunker, chunker_opts} = Keyword.fetch!(opts, :chunker)
      assert Keyword.fetch!(chunker_opts, :page).id == page.id
      assert Keyword.fetch!(chunker_opts, :workspace_id) == ws.id
      blocks = Keyword.fetch!(chunker_opts, :blocks)
      assert is_list(blocks)
      refute Enum.empty?(blocks)
    end

    test "ingests a message's blocks as a message: source (conversation is knowledge)" do
      %{user: user, workspace: ws} = fixtures()

      {:ok, msg} =
        Concept.Knowledge.Chat.create_message(%{text: "see table", addresses_host: false},
          actor: user,
          tenant: ws.id
        )

      {:ok, _block} =
        Concept.Pages.Block
        |> Ash.Changeset.for_create(
          :create_block,
          %{
            container_type: :message,
            container_id: msg.id,
            type: :paragraph,
            content: %{},
            workspace_id: ws.id
          },
          actor: user,
          tenant: ws.id
        )
        |> Ash.create()

      job = %Oban.Job{
        args: %{
          "workspace_id" => ws.id,
          "source_type" => "message",
          "source_id" => msg.id,
          "op" => "upsert"
        }
      }

      assert :ok = IngestPage.perform(job)
      assert_receive {:ingest_called, _text, opts}, 500
      assert opts[:source_id] == "message:#{msg.id}"
      {Concept.Knowledge.BlockChunker, chunker_opts} = Keyword.fetch!(opts, :chunker)
      assert chunker_opts[:message_id] == msg.id
    end
  end
end

defmodule IngestPageTest.MockArcana do
  @moduledoc false
  @subscriber_key {__MODULE__, :subscriber}

  def subscribe(pid), do: :persistent_term.put(@subscriber_key, pid)

  def ingest(text, opts) do
    case :persistent_term.get(@subscriber_key, nil) do
      pid when is_pid(pid) -> send(pid, {:ingest_called, text, opts})
      _ -> :ok
    end

    {:ok, %{chunks: 1}}
  end
end
