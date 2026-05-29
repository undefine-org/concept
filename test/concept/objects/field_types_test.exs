defmodule Concept.Objects.FieldTypesTest do
  @moduledoc "Unit tests for the built-in field types and the registry."
  use ExUnit.Case, async: true

  alias Concept.Objects.FieldTypes

  alias Concept.Objects.FieldTypes.{
    Text,
    Number,
    Select,
    Date,
    Url,
    User,
    Checklist,
    Relation
  }

  describe "registry" do
    test "all built-in types are registered" do
      keys = FieldTypes.all_keys()

      for k <- [:text, :number, :select, :date, :user, :url, :checklist, :relation] do
        assert k in keys, "expected #{k} in registry"
      end
    end

    test "lookup resolves a module; unknown raises" do
      assert FieldTypes.lookup(:text) == Text
      assert_raise FieldTypes.UnknownFieldType, fn -> FieldTypes.lookup(:nope) end
    end

    test "resolve casts a string key safely" do
      assert FieldTypes.resolve("number") == {:ok, :number}
      assert FieldTypes.resolve("bogus_xyz") == {:error, :unknown_type}
    end

    test "relational?/1 is true only for relation" do
      assert FieldTypes.relational?(:relation)
      refute FieldTypes.relational?(:text)
    end
  end

  describe "Text" do
    test "validate accepts strings and nil, rejects others" do
      assert Text.validate("hi", %{}) == :ok
      assert Text.validate(nil, %{}) == :ok
      assert {:error, _} = Text.validate(5, %{})
    end
  end

  describe "Number" do
    test "validate + cast" do
      assert Number.validate(3, %{}) == :ok
      assert {:error, _} = Number.validate("x", %{})
      assert Number.cast("42", %{}) == {:ok, 42}
      assert Number.cast("3.5", %{}) == {:ok, 3.5}
      assert {:error, _} = Number.cast("abc", %{})
    end
  end

  describe "Select" do
    test "validate constrains to options" do
      cfg = %{"options" => ["low", "high"]}
      assert Select.validate("low", cfg) == :ok
      assert {:error, _} = Select.validate("mid", cfg)
    end

    test "json_schema emits an enum" do
      assert %{"enum" => ["a", "b"]} = Select.json_schema(%{"options" => ["a", "b"]})
    end
  end

  describe "Date" do
    test "validate iso8601" do
      assert Date.validate("2026-05-29", %{}) == :ok
      assert {:error, _} = Date.validate("29/05/2026", %{})
    end
  end

  describe "Url" do
    test "validate scheme + host" do
      assert Url.validate("https://example.com", %{}) == :ok
      assert {:error, _} = Url.validate("not a url", %{})
      assert {:error, _} = Url.validate("ftp://x", %{})
    end
  end

  describe "User" do
    test "validate uuid" do
      assert User.validate(Ecto.UUID.generate(), %{}) == :ok
      assert {:error, _} = User.validate("nope", %{})
    end
  end

  describe "Checklist" do
    test "validate items and complete?" do
      items = [%{"label" => "a", "checked" => true}, %{"label" => "b", "checked" => false}]
      assert Checklist.validate(items, %{}) == :ok
      refute Checklist.complete?(items)
      assert Checklist.complete?([%{"label" => "a", "checked" => true}])
      assert Checklist.complete?([])
    end

    test "cast normalizes bare strings" do
      assert {:ok, [%{"label" => "x", "checked" => false}]} = Checklist.cast(["x"], %{})
    end
  end

  describe "Relation" do
    test "single vs many shape" do
      id = Ecto.UUID.generate()
      assert Relation.validate(id, %{}) == :ok
      assert {:error, _} = Relation.validate([id], %{})
      assert Relation.validate([id], %{"many" => true}) == :ok
      assert Relation.default(%{"many" => true}) == []
      assert Relation.relational?()
    end
  end
end
