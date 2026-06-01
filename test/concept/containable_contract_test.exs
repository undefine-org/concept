defmodule Concept.ContainableContractTest do
  @moduledoc """
  Structural contract for the block-container registry — the permanent guard
  that the persisted `Block.container_type` discriminator can never drift from
  `config :concept, :containables`. Mirrors `BlockTypeContractTest` and
  `HostableTest`: assertions over the *whole* registry, not spot checks.

    * C1 — every registered container declares `__containable__/0` with a `type`.
    * C2 — `types/0` is the exact, duplicate-free projection of the registry.
    * C3 — `module_for/1` round-trips every registered type, and rejects unknowns.
    * C4 — `TypeAttr` accepts every registered type (atom and string) and
            rejects unregistered / malformed input — the write-time validation.
  """
  use ExUnit.Case, async: true

  alias Concept.Containable
  alias Concept.Containable.TypeAttr

  describe "C1 — registry membership" do
    test "Page and Message are registered containers" do
      assert Concept.Pages.Page in Containable.registered()
      assert Concept.Knowledge.Chat.Message in Containable.registered()
    end

    test "every registered module declares __containable__/0 with an atom type" do
      for mod <- Containable.registered() do
        meta = mod.__containable__()
        assert is_map(meta), "#{inspect(mod)} __containable__/0 must return a map"
        assert is_atom(meta.type), "#{inspect(mod)} must declare an atom :type"
      end
    end
  end

  describe "C2 — types/0 projection" do
    test "types/0 is exactly the registry's declared types" do
      expected = Enum.map(Containable.registered(), & &1.__containable__().type)
      assert Containable.types() == expected
    end

    test "types/0 has no duplicates (each discriminator is unique)" do
      types = Containable.types()
      assert length(types) == length(Enum.uniq(types)), "duplicate container_type in registry"
    end

    test "the built-in containers are present" do
      assert :page in Containable.types()
      assert :message in Containable.types()
    end
  end

  describe "C3 — module_for/1" do
    test "round-trips every registered type back to its module" do
      for mod <- Containable.registered() do
        type = mod.__containable__().type
        assert Containable.module_for(type) == mod
      end
    end

    test "returns nil for an unregistered type" do
      assert Containable.module_for(:nonexistent) == nil
    end
  end

  describe "C4 — TypeAttr write-time validation" do
    test "accepts every registered type as an atom" do
      for type <- Containable.types() do
        assert {:ok, ^type} = TypeAttr.cast_input(type, [])
      end
    end

    test "accepts every registered type as a string" do
      for type <- Containable.types() do
        assert {:ok, ^type} = TypeAttr.cast_input(Atom.to_string(type), [])
      end
    end

    test "rejects an unregistered atom" do
      assert {:error, _} = TypeAttr.cast_input(:workspace, [])
    end

    test "rejects an unknown string without leaking atoms" do
      assert {:error, _} =
               TypeAttr.cast_input("definitely_not_a_container_#{System.unique_integer()}", [])
    end

    test "round-trips through storage (dump → cast_stored)" do
      for type <- Containable.types() do
        {:ok, stored} = TypeAttr.dump_to_native(type, [])
        assert is_binary(stored)
        assert {:ok, ^type} = TypeAttr.cast_stored(stored, [])
      end
    end

    test "nil passes through (container_type nullability is the schema's call, not the type's)" do
      assert {:ok, nil} = TypeAttr.cast_input(nil, [])
      assert {:ok, nil} = TypeAttr.cast_stored(nil, [])
    end
  end
end
