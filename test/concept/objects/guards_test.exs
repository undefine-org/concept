defmodule Concept.Objects.GuardsTest do
  @moduledoc "Unit tests for transition guards and the guard registry."
  use ExUnit.Case, async: true

  alias Concept.Objects.Guards

  alias Concept.Objects.Guards.{
    RequiresApproval,
    RequiresProof,
    RequiresChecklistComplete,
    RequiresFields
  }

  describe "registry" do
    test "all built-in guards registered" do
      kinds = Guards.all_kinds()

      for k <- [
            :requires_approval,
            :requires_proof,
            :requires_checklist_complete,
            :requires_fields
          ] do
        assert k in kinds
      end
    end

    test "lookup by string and atom" do
      assert {:ok, RequiresProof} = Guards.lookup("requires_proof")
      assert {:ok, RequiresProof} = Guards.lookup(:requires_proof)
      assert {:error, :unknown} = Guards.lookup("nope_guard")
    end

    test "describe_all renders composed guard phrases" do
      specs = [
        %{"kind" => "requires_approval", "config" => %{"by" => "creator"}},
        %{"kind" => "requires_proof", "config" => %{"field" => "pr_url"}}
      ]

      phrases = Guards.describe_all(specs)
      assert Enum.any?(phrases, &(&1 =~ "approval"))
      assert Enum.any?(phrases, &(&1 =~ "pr_url"))
    end
  end

  describe "RequiresApproval" do
    test "creator may approve, others may not" do
      record = %{created_by_id: "u1", fields: %{}}
      assert RequiresApproval.check(record, %{"by" => "creator"}, %{actor: %{id: "u1"}}) == :ok

      assert {:error, _} =
               RequiresApproval.check(record, %{"by" => "creator"}, %{actor: %{id: "u2"}})
    end

    test "anyone policy allows any actor" do
      record = %{created_by_id: "u1", fields: %{}}
      assert RequiresApproval.check(record, %{"by" => "anyone"}, %{actor: %{id: "u9"}}) == :ok
    end

    test "nil actor blocked" do
      assert {:error, _} = RequiresApproval.check(%{created_by_id: "u1"}, %{}, %{actor: nil})
    end
  end

  describe "RequiresProof" do
    test "present field passes; missing fails" do
      assert RequiresProof.check(
               %{fields: %{"pr_url" => "http://x"}},
               %{"field" => "pr_url"},
               %{}
             ) == :ok

      assert {:error, _} = RequiresProof.check(%{fields: %{}}, %{"field" => "pr_url"}, %{})

      assert {:error, _} =
               RequiresProof.check(%{fields: %{"pr_url" => ""}}, %{"field" => "pr_url"}, %{})
    end
  end

  describe "RequiresChecklistComplete" do
    test "complete passes; incomplete fails" do
      done = %{fields: %{"acc" => [%{"label" => "a", "checked" => true}]}}
      todo = %{fields: %{"acc" => [%{"label" => "a", "checked" => false}]}}
      assert RequiresChecklistComplete.check(done, %{"field" => "acc"}, %{}) == :ok
      assert {:error, _} = RequiresChecklistComplete.check(todo, %{"field" => "acc"}, %{})
    end
  end

  describe "RequiresFields" do
    test "all present passes; any missing fails with names" do
      rec = %{fields: %{"owner" => "me", "due" => nil}}
      assert RequiresFields.check(rec, %{"fields" => ["owner"]}, %{}) == :ok
      assert {:error, msg} = RequiresFields.check(rec, %{"fields" => ["owner", "due"]}, %{})
      assert msg =~ "due"
    end
  end
end
