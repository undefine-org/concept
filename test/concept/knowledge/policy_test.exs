defmodule Concept.Knowledge.PolicyTest do
  use ExUnit.Case, async: true

  describe "WorkspaceArgumentMember check" do
    test "module exists and exports required callbacks" do
      assert Code.ensure_loaded?(Concept.Knowledge.Checks.WorkspaceArgumentMember)
      assert function_exported?(Concept.Knowledge.Checks.WorkspaceArgumentMember, :describe, 1)
      assert function_exported?(Concept.Knowledge.Checks.WorkspaceArgumentMember, :check, 4)
    end
  end
end
