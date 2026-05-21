ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Concept.Repo, :manual)

# Treat specific Ash misuse warnings as hard test failures.
# See `Concept.Test.AshWarningFilter` for the pattern list and rationale.
Concept.Test.AshWarningFilter.attach()
