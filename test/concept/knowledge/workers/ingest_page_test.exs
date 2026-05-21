defmodule Concept.Knowledge.Workers.IngestPageTest do
  @moduledoc """
  BUG-049 — IngestPage worker must call `Pages.list_for_page/2` with a
  positional `page_id`, not a keyword list. Previously the call was
  `list_for_page(page_id: page_id, actor: actor, tenant: workspace_id)`,
  which made every ingestion fail with
  `Ash.Error.Query.InvalidArgument{field: :page_id, …}` and dead-lettered
  every Oban job.

  Also asserts the worker hands the loaded page + blocks to `Arcana.ingest/2`
  via `chunker_opts` so the custom `Concept.Knowledge.BlockChunker` can build
  chunks deterministically.
  """
  use Concept.DataCase, async: false

  alias Concept.{Accounts, Pages}
  alias Concept.Knowledge.Workers.IngestPage

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
      Pages.create_block(page.id, :paragraph, workspace.id, nil,
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

    test "passes the loaded page + blocks to Arcana via chunker_opts" do
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
      chunker_opts = Keyword.fetch!(opts, :chunker_opts)
      assert Keyword.fetch!(chunker_opts, :page).id == page.id
      assert Keyword.fetch!(chunker_opts, :workspace_id) == ws.id
      blocks = Keyword.fetch!(chunker_opts, :blocks)
      assert is_list(blocks)
      refute Enum.empty?(blocks)
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
