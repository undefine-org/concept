# Concept Credo config.
#
# Lean: only the project-specific architectural rule is enforced.
# Stylistic defaults are off so this doesn't compete with mix format.
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/", ~r"/priv/"]
      },
      strict: true,
      color: true,
      checks: %{
        enabled: [
          {Concept.Credo.Check.LiveViewPurity, []}
        ],
        # Disable Credo's default rule set — we use mix format for style.
        disabled: []
      }
    }
  ]
}
