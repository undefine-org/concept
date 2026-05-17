defmodule Mix.Tasks.Concept.Demo do
  @shortdoc "Seed a demo workspace showcasing Arcana awareness"
  @moduledoc """
  Seeds a `demo@concept.local` user + workspace with rich content:

  - 4 pages w/ paragraphs, headings, todos, callouts, and one :ai_answer block
  - Pre-seeded Conversation + answered Message + 2 Citations
  - 3 Links between blocks (`relates_to`, `:cites`, `:contradicts`)
  - Token ledger entries (light)

  Idempotent: re-running upserts cleanly.
  """

  use Mix.Task

  require Ash.Query
  import Ecto.Query, only: [from: 2]

  alias Concept.Accounts
  alias Concept.Pages
  alias Concept.Knowledge
  alias Concept.Knowledge.SystemActor

  @demo_email "demo@concept.local"
  @demo_password "demo-password-12345"

  @page_specs [
    %{
      title: "Welcome to Concept",
      blocks: [
        {:heading_1, "Welcome to Concept"},
        {:paragraph,
         "Concept is an awareness substrate for your ideas. It combines a Notion-style editor with Arcana-powered knowledge graphing and AshAI conversational intelligence."},
        {:heading_2, "Getting Started"},
        {:paragraph,
         "Every page you create is automatically indexed into a searchable knowledge graph. Use ⌘K to search semantically across your workspace."},
        {:to_do, "Try creating a new page with ⌘K", false},
        {:to_do, "Open the chat panel with ⌘J and ask a question", false},
        {:callout,
         "Tip: Type / in the editor to open the slash menu and insert an AI Answer block.", "💡",
         "default"}
      ]
    },
    %{
      title: "Distributed Systems Notes",
      blocks: [
        {:heading_1, "Distributed Systems Notes"},
        {:heading_2, "CAP Theorem"},
        {:paragraph,
         "The CAP theorem states that a distributed data store cannot simultaneously provide more than two of the following: Consistency, Availability, and Partition Tolerance. In practice, partition tolerance is mandatory, so the real trade-off is between consistency and availability."},
        {:heading_2, "Consensus"},
        {:paragraph,
         "Consensus algorithms like Raft and Paxos allow distributed systems to agree on a single value despite failures. Raft achieves this through leader election and log replication, prioritizing understandability over optimality."},
        {:heading_2, "Vector Clocks"},
        {:paragraph,
         "Vector clocks track the happens-before relationship across distributed nodes. Each node maintains a vector of counters; by comparing vectors, we can determine if events are concurrent or ordered."}
      ]
    },
    %{
      title: "Machine Learning Glossary",
      blocks: [
        {:heading_1, "Machine Learning Glossary"},
        {:heading_2, "Embeddings"},
        {:paragraph,
         "Embeddings are dense vector representations of data (text, images, audio) that capture semantic meaning. Similar items cluster together in the embedding space, enabling nearest-neighbor search and retrieval."},
        {:heading_2, "Attention"},
        {:paragraph,
         "Attention mechanisms let models focus on specific parts of the input when producing each part of the output. Self-attention, popularized by Transformers, computes relationships between all positions in a sequence simultaneously."},
        {:heading_2, "Retrieval-Augmented Generation"},
        {:paragraph,
         "RAG augments large language models with external knowledge retrieval. Instead of relying solely on parametric memory, the model retrieves relevant documents and grounds its answer in retrieved context, reducing hallucinations."}
      ]
    },
    %{
      title: "Roadmap",
      blocks: [
        {:heading_1, "Roadmap"},
        {:to_do, "Ship v1.0 with full block support", true},
        {:to_do, "Add real-time collaboration cursors", false},
        {:to_do, "Integrate external MCP tools", false},
        {:to_do, "Build mobile-native editor", false},
        {:callout,
         "Remember: awareness surfaces only matter if users can find them. Empty states should teach, not scold.",
         "🚀", "default"},
        {:ai_answer, "What should we prioritize next?", :workspace}
      ]
    }
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    if Mix.env() == :prod do
      Mix.shell().info("⚠️  concept.demo is intended for development. Proceed with caution.")
    end

    user = find_or_create_user!()
    ws = get_and_rename_workspace!(user)

    demo_titles = Enum.map(@page_specs, & &1.title)

    existing_pages =
      Concept.Pages.Page
      |> Ash.Query.filter(workspace_id == ^ws.id and title in ^demo_titles)
      |> Ash.read!(actor: user, tenant: ws.id)

    existing_titles = Enum.map(existing_pages, & &1.title)

    pages =
      for spec <- @page_specs do
        if spec.title in existing_titles do
          Enum.find(existing_pages, &(&1.title == spec.title))
        else
          {:ok, page} = Pages.create_page(spec.title, ws.id, nil, actor: user, tenant: ws.id)
          page
        end
      end

    blocks_by_title =
      for {spec, page} <- Enum.zip(@page_specs, pages), into: %{} do
        blocks =
          if spec.title in existing_titles do
            {:ok, blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
            blocks
          else
            create_page_blocks!(page, spec.blocks, ws, user)
          end

        {spec.title, blocks}
      end

    ds_blocks = blocks_by_title["Distributed Systems Notes"] || []
    roadmap_blocks = blocks_by_title["Roadmap"] || []

    {_conv, _user_msg, agent_msg} = seed_conversation!(user)

    seed_citations!(agent_msg, ds_blocks, pages, ws)
    seed_links!(ds_blocks, ws, user)
    seed_token_ledger!(ws)
    update_ai_block!(roadmap_blocks, agent_msg, ws, user)

    print_cheat_sheet(ws)
  end

  defp find_or_create_user! do
    case Accounts.User
         |> Ash.Query.filter(email == ^@demo_email)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        {:ok, user} =
          Accounts.User
          |> Ash.Changeset.for_create(:register_with_password, %{
            email: @demo_email,
            password: @demo_password,
            password_confirmation: @demo_password
          })
          |> Ash.create(authorize?: false)

        ensure_confirmed!(user)

      {:ok, user} ->
        ensure_confirmed!(user)
    end
  end

  defp ensure_confirmed!(%{confirmed_at: nil} = user) do
    # Auto-confirm: skip the email confirmation flow for the demo user.
    # There is no Ash action for this; using Ecto is the pragmatic path here.
    now = DateTime.utc_now()

    Concept.Repo.update_all(
      from(u in Accounts.User, where: u.id == ^user.id),
      set: [confirmed_at: now]
    )

    %{user | confirmed_at: now}
  end

  defp ensure_confirmed!(user), do: user

  defp get_and_rename_workspace!(user) do
    {:ok, [ws]} = Accounts.Workspace.for_user(user.id, actor: user)

    case Accounts.Workspace.rename(ws, "Concept Demo", actor: user) do
      {:ok, renamed} -> renamed
      {:error, _} -> ws
    end
  end

  defp create_page_blocks!(page, blocks, ws, user) do
    Enum.map(blocks, fn spec ->
      try do
        create_block!(page, spec, ws, user)
      rescue
        e ->
          Mix.shell().info(
            "Warning: block creation raised on #{page.title}: #{Exception.message(e)}"
          )

          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp create_block!(page, {:paragraph, text}, ws, user) do
    Concept.Pages.Block
    |> Ash.Changeset.for_create(:create_block, %{
      page_id: page.id,
      type: :paragraph,
      content: Concept.Lexical.from_plain_text(text, "paragraph"),
      workspace_id: ws.id
    })
    |> Ash.create!(actor: user, tenant: ws.id)
  end

  defp create_block!(page, {:heading_1, text}, ws, user) do
    Concept.Pages.Block
    |> Ash.Changeset.for_create(:create_block, %{
      page_id: page.id,
      type: :heading_1,
      content: heading_content(text, 1),
      workspace_id: ws.id
    })
    |> Ash.create!(actor: user, tenant: ws.id)
  end

  defp create_block!(page, {:heading_2, text}, ws, user) do
    Concept.Pages.Block
    |> Ash.Changeset.for_create(:create_block, %{
      page_id: page.id,
      type: :heading_2,
      content: heading_content(text, 2),
      workspace_id: ws.id
    })
    |> Ash.create!(actor: user, tenant: ws.id)
  end

  defp create_block!(page, {:to_do, text, checked}, ws, user) do
    Concept.Pages.Block
    |> Ash.Changeset.for_create(:create_block, %{
      page_id: page.id,
      type: :to_do,
      content: Concept.Lexical.from_plain_text(text, "paragraph"),
      props: %{"checked" => checked},
      workspace_id: ws.id
    })
    |> Ash.create!(actor: user, tenant: ws.id)
  end

  defp create_block!(page, {:callout, text, emoji, color}, ws, user) do
    Concept.Pages.Block
    |> Ash.Changeset.for_create(:create_block, %{
      page_id: page.id,
      type: :callout,
      content: Concept.Lexical.from_plain_text(text, "paragraph"),
      props: %{"emoji" => emoji, "color" => color},
      workspace_id: ws.id
    })
    |> Ash.create!(actor: user, tenant: ws.id)
  end

  defp create_block!(page, {:ai_answer, prompt, scope}, ws, user) do
    Concept.Pages.Block
    |> Ash.Changeset.for_create(:create_block, %{
      page_id: page.id,
      type: :ai_answer,
      props: %{"prompt" => prompt, "scope" => to_string(scope)},
      workspace_id: ws.id
    })
    |> Ash.create!(actor: user, tenant: ws.id)
  end

  defp heading_content(text, level) do
    %{
      "root" => %{
        "type" => "root",
        "children" => [
          %{
            "type" => "heading",
            "tag" => "h#{level}",
            "children" => [
              %{
                "type" => "text",
                "text" => text,
                "format" => 0,
                "detail" => 0,
                "mode" => "normal",
                "style" => "",
                "version" => 1
              }
            ],
            "direction" => "ltr",
            "format" => "",
            "indent" => 0,
            "version" => 1
          }
        ],
        "direction" => "ltr",
        "format" => "",
        "indent" => 0,
        "version" => 1
      }
    }
  end

  defp seed_conversation!(user) do
    {:ok, conv} =
      Concept.Knowledge.Chat.create_conversation(%{title: "Demo Conversation"},
        actor: user,
        authorize?: false
      )

    {:ok, user_msg} =
      Concept.Knowledge.Chat.Message
      |> Ash.Changeset.new()
      |> Ash.Changeset.set_argument(:conversation_id, conv.id)
      |> Ash.Changeset.for_create(:create, %{
        text: "What is the relationship between the CAP theorem and consensus algorithms?"
      })
      |> Ash.create(actor: user, authorize?: false)

    agent_msg =
      Concept.Knowledge.Chat.Message
      |> Ash.Changeset.for_create(:upsert_response, %{
        id: Ash.UUIDv7.generate(),
        conversation_id: conv.id,
        response_to_id: user_msg.id,
        text: """
        The CAP theorem and consensus algorithms are deeply intertwined. Consensus protocols like Raft and Paxos essentially choose availability or consistency under network partitions.

        Raft guarantees strong consistency by requiring a majority quorum, sacrificing availability when partitions isolate the leader. In contrast, eventually consistent systems favor availability but may return stale reads. Both are practical responses to the fundamental limits CAP describes.
        """,
        complete: true
      })
      |> Ash.create!(actor: %SystemActor{}, authorize?: false)

    {conv, user_msg, agent_msg}
  end

  defp seed_citations!(agent_msg, ds_blocks, pages, ws) do
    ds_page = Enum.find(pages, &(&1.title == "Distributed Systems Notes"))
    para_blocks = Enum.filter(ds_blocks, &(&1.type == :paragraph))

    if length(para_blocks) >= 2 and ds_page do
      [cap_block, consensus_block | _] = para_blocks

      Knowledge.create_citation(
        %{
          workspace_id: ws.id,
          message_id: agent_msg.id,
          block_id: cap_block.id,
          page_id: ds_page.id,
          rank: 1,
          score: 0.95,
          snippet:
            "The CAP theorem states that a distributed data store cannot simultaneously provide more than two of the following...",
          breadcrumbs: "Distributed Systems Notes > CAP Theorem"
        },
        actor: %SystemActor{},
        tenant: ws.id
      )

      Knowledge.create_citation(
        %{
          workspace_id: ws.id,
          message_id: agent_msg.id,
          block_id: consensus_block.id,
          page_id: ds_page.id,
          rank: 2,
          score: 0.88,
          snippet:
            "Consensus algorithms like Raft and Paxos allow distributed systems to agree on a single value despite failures...",
          breadcrumbs: "Distributed Systems Notes > Consensus"
        },
        actor: %SystemActor{},
        tenant: ws.id
      )
    end
  end

  defp seed_links!(ds_blocks, ws, user) do
    para_blocks = Enum.filter(ds_blocks, &(&1.type == :paragraph))

    if length(para_blocks) >= 3 do
      [b1, b2, b3 | _] = para_blocks

      for {source, target, kind, note} <- [
            {b1, b2, :relates_to, "Both deal with distributed consistency"},
            {b2, b3, :cites, "Consensus builds on logical ordering"},
            {b1, b3, :contradicts, "CAP implies trade-offs; vector clocks enable concurrency"}
          ] do
        try do
          Knowledge.create_link(
            %{
              workspace_id: ws.id,
              source_block_id: source.id,
              target_block_id: target.id,
              kind: kind,
              note: note
            },
            actor: user,
            tenant: ws.id
          )
        rescue
          _ -> :ok
        end
      end
    end
  end

  defp seed_token_ledger!(ws) do
    today = Date.utc_today()
    yesterday = Date.add(today, -1)

    for day <- [today, yesterday] do
      Knowledge.TokenLedger
      |> Ash.Changeset.for_create(:upsert, %{
        workspace_id: ws.id,
        day: day,
        prompt_tokens: Enum.random(500..2000),
        completion_tokens: Enum.random(300..1500),
        embed_tokens: Enum.random(100..800),
        request_count: Enum.random(1..10)
      })
      |> Ash.create!(actor: %SystemActor{}, tenant: ws.id)
    end
  end

  defp update_ai_block!(roadmap_blocks, agent_msg, _ws, _user) do
    case Enum.find(roadmap_blocks, &(&1.type == :ai_answer)) do
      nil ->
        :ok

      block ->
        # Bypass the lock requirement: this is a one-time seed script.
        import Ecto.Query

        Concept.Repo.update_all(
          from(b in Concept.Pages.Block, where: b.id == ^block.id),
          set: [content: %{"message_id" => agent_msg.id}]
        )

        :ok
    end
  end

  defp print_cheat_sheet(ws) do
    IO.puts("""
    🎉 Demo workspace ready!

      URL:      http://localhost:4000/w/#{ws.slug}
      Login:    #{@demo_email} / #{@demo_password}

    Try:
      ⌘K        Command palette (semantic search)
      ⌘J        Open chat panel
      /         Slash menu in editor (✨ AI answer is the magic one)
      /w/.../graph  Workspace knowledge graph
      /admin    Ash admin (lists all Knowledge resources)
      /mcp      MCP endpoint (mint an API key in /admin/accounts/api-keys)

    See docs/CONCEPT_HOWTO.md for the full tour.
    """)
  end
end
