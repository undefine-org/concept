defmodule Concept.Knowledge.Chat.CrystallizePropertyTest do
  @moduledoc """
  Round-trip property for crystallization — the one operation that *moves a
  block forest across containers* (message → page). If blocks are truly
  container-agnostic content (the Container thesis), re-homing them must be a
  structure-preserving map.

  For a randomly generated forest of message blocks, after crystallize the page
  tree must satisfy:

    * P-order — within every parent, children keep their left-to-right order
      (the FractionalIndex order from W0).
    * P-shape — the parent/child hierarchy is isomorphic: the (parent-signature
      → child-signatures) relation on the page equals that of the message,
      under the natural content-signature labelling. This catches any
      parent-remap (`id_map`) error in `CloneBlocks`.

  Each block carries a unique content tag so the two trees can be aligned
  without relying on ids (which differ — clone mints new ones). Exercises W0
  ordering + W2 schema + W3 dispatch together.
  """
  use Concept.DataCase, async: false
  use ExUnitProperties

  alias Concept.Knowledge.Chat
  alias Concept.Pages

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "cryst-prop-#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws | _]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)
    %{user: user, ws: ws}
  end

  # A forest spec: a list of top-level nodes, each `{tag, [child_specs]}` to one
  # level of nesting (toggles/paragraphs — enough to exercise parent remap and
  # sibling ordering without unbounded depth).
  defp forest_gen do
    child_gen =
      StreamData.bind(StreamData.integer(0..3), fn n ->
        StreamData.constant(n)
      end)

    StreamData.list_of(child_gen, min_length: 1, max_length: 4)
  end

  property "crystallize preserves sibling order and tree shape", %{user: u, ws: ws} do
    check all(child_counts <- forest_gen(), max_runs: 25) do
      # Fresh page + message per run (async: false; sandbox). The message
      # find-or-creates its own workspace-host conversation; crystallize gathers
      # blocks by THAT conversation_id, so use it (not a detached conversation).
      {:ok, page} = Pages.create_page("P", ws.id, nil, actor: u, tenant: ws.id)

      {:ok, msg} =
        Chat.create_message(%{text: "seed", addresses_host: false}, actor: u, tenant: ws.id)

      conv_id = msg.conversation_id

      tag = "t#{System.unique_integer([:positive])}"

      # Build the message forest: top-level parents in order, each with N
      # ordered children. Tags encode position so we can assert order + shape.
      expected =
        child_counts
        |> Enum.with_index()
        |> Enum.map(fn {n_children, p_idx} ->
          parent_tag = "#{tag}-p#{p_idx}"

          {:ok, parent} =
            Pages.create_block(:message, msg.id, :toggle, ws.id, nil,
              actor: u,
              tenant: ws.id
            )

          {:ok, _} =
            Pages.update_content(parent, %{"text" => parent_tag}, actor: u, tenant: ws.id)

          child_tags =
            for c_idx <- 0..(n_children - 1)//1 do
              child_tag = "#{parent_tag}-c#{c_idx}"

              {:ok, child} =
                Pages.create_block(:message, msg.id, :paragraph, ws.id, parent.id,
                  actor: u,
                  tenant: ws.id
                )

              {:ok, _} =
                Pages.update_content(child, %{"text" => child_tag}, actor: u, tenant: ws.id)

              child_tag
            end

          {parent_tag, child_tags}
        end)

      {:ok, _} = Chat.crystallize_conversation(conv_id, page.id, ws.id, actor: u, tenant: ws.id)

      {:ok, page_blocks} = Pages.list_for_page(page.id, actor: u, tenant: ws.id)

      # Index page blocks by content tag, and by id for parent lookup.
      by_id = Map.new(page_blocks, &{&1.id, &1})
      tag_of = fn b -> get_in(b.content, ["text"]) end

      # P-shape + P-order: reconstruct (parent_tag -> [child_tags in order]) from
      # the page and compare to the expected message structure.
      actual =
        page_blocks
        |> Enum.filter(&(&1.type == :toggle))
        |> Enum.sort_by(& &1.position)
        |> Enum.map(fn parent ->
          children =
            page_blocks
            |> Enum.filter(&(&1.parent_block_id == parent.id))
            |> Enum.sort_by(& &1.position)
            |> Enum.map(tag_of)

          {tag_of.(parent), children}
        end)

      assert actual == expected,
             "crystallized tree must match message tree in order and shape\n" <>
               "expected: #{inspect(expected)}\nactual:   #{inspect(actual)}"

      # Every cloned child's parent is itself a cloned page block (bijective
      # remap, no dangling parent pointer into the message tree).
      for b <- page_blocks, not is_nil(b.parent_block_id) do
        assert Map.has_key?(by_id, b.parent_block_id),
               "child #{inspect(tag_of.(b))} points at a parent not on the page"
      end
    end
  end
end
