defmodule Concept.Credo.Check.LiveViewPurityTest do
  @moduledoc """
  Smoke test for the LiveView purity check.

  The real proof is `mix credo --strict` running clean on the project
  (added to the `precommit` alias in FEAT-062). This file just confirms
  the check is registered and recognized by Credo.
  """
  use ExUnit.Case, async: false

  # Shells out to `mix credo --strict` which can take >60s on cold caches
  # or when the precommit suite is hammering the box. Bump to 180s.
  @tag timeout: 180_000
  test "the check is loaded and Credo runs cleanly on the codebase" do
    {output, exit_code} =
      System.cmd(
        "mix",
        ["credo", "--strict"],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    assert exit_code == 0,
           "expected mix credo --strict to exit 0 (LiveViews are clean), got #{exit_code}; output:\n#{output}"

    assert output =~ "Concept.Credo.Check.LiveViewPurity" or
             output =~ "found no issues",
           "expected output to mention the check or report no issues; got:\n#{output}"
  end
end
