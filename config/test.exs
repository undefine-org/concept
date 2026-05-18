import Config
config :concept, Oban, testing: :manual
config :concept, token_signing_secret: "7VblMjWeJHZb37nzIMPv0V61eHKpxzAO"
config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Use deterministic offline embedder for tests — no network, reproducible vectors.
config :arcana,
  embedder: Concept.Knowledge.MockEmbedder,
  chunker: Concept.Knowledge.BlockChunker,
  search: [mode: :hybrid, limit: 10]

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :concept, Concept.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "concept_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :concept, ConceptWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "i+h1Oj3z5bUVOl4Nnon+gmcN3rlE3v1gHPZNIssXJMx3tq+KBqANRxV/gVtKfW3Q",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Concept.AutoTools opt-out deny list. Compiled into the test fixture domains.
config :concept, Concept.AutoTools,
  exclude: [
    {Concept.AutoToolsFixtures.FixtureResource, :excluded_read}
  ]

