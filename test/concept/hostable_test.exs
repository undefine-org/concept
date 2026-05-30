defmodule Concept.HostableTest do
  @moduledoc """
  Wave 0 keystone tests: the Hostable registry, host_type validation on
  Conversation, and the host-derived grounding scope. These assert the data
  model that the whole conversation substrate rests on (PLAN-010).
  """
  use Concept.DataCase, async: true

  alias Concept.Hostable

  describe "registry" do
    test "Page is a registered hostable" do
      assert Concept.Pages.Page in Hostable.registered()
    end

    test "types/0 includes the built-in :workspace and every registered host's type" do
      types = Hostable.types()
      assert :workspace in types
      assert :page in types
    end

    test "module_for/1 maps a type atom to its module; :workspace has no module" do
      assert Hostable.module_for(:page) == Concept.Pages.Page
      assert Hostable.module_for(:workspace) == nil
      assert Hostable.module_for(:nonexistent) == nil
    end
  end

  describe "Page as a host" do
    test "declares its hostable metadata" do
      meta = Concept.Pages.Page.__hostable__()
      assert meta.type == :page
      assert meta.scope == :subtree
    end

    test "subgraph_scope/1 grounds a page conversation in that page's source" do
      page = %Concept.Pages.Page{id: "11111111-1111-1111-1111-111111111111"}

      assert Concept.Pages.Page.subgraph_scope(page) ==
               {:source_id, "page:11111111-1111-1111-1111-111111111111"}
    end
  end

  describe "scope resolution" do
    test "the workspace host grounds across the whole tenant" do
      assert Hostable.scope_for(:workspace, nil, []) == :workspace
    end

    test "resolve_scope/2 translates declared scopes to retrieval filters" do
      record = %{id: "abc"}
      assert Hostable.resolve_scope(:subtree, record) == {:source_id, "page:abc"}
      assert Hostable.resolve_scope({:self, []}, record) == {:source_id, "record:abc"}
      assert Hostable.resolve_scope(:workspace, record) == :workspace
      assert Hostable.resolve_scope({:union, [:a, :b]}, record) == {:union, [:a, :b]}
    end
  end
end
