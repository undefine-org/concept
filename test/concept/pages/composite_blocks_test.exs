defmodule Concept.Pages.CompositeBlocksTest do
  @moduledoc """
  Domain tests for FEAT-050 composite blocks.

  Covers: bulk creation reactors (`create_table/5`, `create_columns/4`),
  row-major cell ordering, and cascading archive of children.
  """
  use Concept.DataCase, async: false

  alias Concept.Pages

  setup do
    {:ok, user} =
      Concept.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "composite_#{System.unique_integer([:positive])}@example.com",
        password: "passw0rd!",
        password_confirmation: "passw0rd!"
      })
      |> Ash.create(authorize?: false)

    {:ok, [ws]} = Concept.Accounts.Workspace.for_user(user.id, actor: user)

    {:ok, page} = Pages.create_page("CompositeTest", ws.id, nil, actor: user, tenant: ws.id)

    %{user: user, ws: ws, page: page}
  end

  describe "create_table/5" do
    test "creates 1 Table parent + rows*cols TableCell children", %{
      user: user,
      ws: ws,
      page: page
    } do
      {:ok, parent} =
        Pages.create_table(ws.id, page.id, 2, 3, actor: user, tenant: ws.id)

      assert parent.type == :table
      assert parent.parent_block_id == nil
      assert parent.props["rows"] == 2
      assert parent.props["cols"] == 3

      {:ok, all_blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
      assert length(all_blocks) == 1 + 2 * 3

      cells = Enum.filter(all_blocks, &(&1.parent_block_id == parent.id))
      assert length(cells) == 6
      assert Enum.all?(cells, &(&1.type == :table_cell))
    end

    test "cells ordered row-major (row 0 col 0..n-1, row 1 col 0..n-1)", %{
      user: user,
      ws: ws,
      page: page
    } do
      {:ok, parent} =
        Pages.create_table(ws.id, page.id, 2, 3, actor: user, tenant: ws.id)

      {:ok, all_blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)

      cells =
        all_blocks
        |> Enum.filter(&(&1.parent_block_id == parent.id))
        |> Enum.sort_by(& &1.position)

      indices =
        Enum.map(cells, fn c ->
          {c.props["row_index"], c.props["col_index"]}
        end)

      assert indices == [{0, 0}, {0, 1}, {0, 2}, {1, 0}, {1, 1}, {1, 2}]
    end
  end

  describe "create_columns/4" do
    test "creates 1 Columns parent + N Column children", %{
      user: user,
      ws: ws,
      page: page
    } do
      {:ok, parent} =
        Pages.create_columns(ws.id, page.id, 3, actor: user, tenant: ws.id)

      assert parent.type == :columns
      assert parent.parent_block_id == nil
      assert parent.props["count"] == 3

      {:ok, all_blocks} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
      assert length(all_blocks) == 1 + 3

      children =
        all_blocks
        |> Enum.filter(&(&1.parent_block_id == parent.id))
        |> Enum.sort_by(& &1.position)

      assert length(children) == 3
      assert Enum.all?(children, &(&1.type == :column))
    end
  end

  describe "archive cascade" do
    test "archiving table parent archives its TableCell children", %{
      user: user,
      ws: ws,
      page: page
    } do
      {:ok, parent} =
        Pages.create_table(ws.id, page.id, 2, 2, actor: user, tenant: ws.id)

      {:ok, _} = Pages.archive_block(parent, actor: user, tenant: ws.id)

      {:ok, remaining} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
      assert remaining == []
    end

    test "archiving columns parent archives its Column children", %{
      user: user,
      ws: ws,
      page: page
    } do
      {:ok, parent} =
        Pages.create_columns(ws.id, page.id, 3, actor: user, tenant: ws.id)

      {:ok, _} = Pages.archive_block(parent, actor: user, tenant: ws.id)

      {:ok, remaining} = Pages.list_for_page(page.id, actor: user, tenant: ws.id)
      assert remaining == []
    end
  end
end
