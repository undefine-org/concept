defmodule Concept.Knowledge.MockEmbedder do
  @moduledoc """
  Deterministic, offline embedder for tests. Implements `Arcana.Embedder`.

  Vector is derived from a SHA-256 of the input text, projected into 384 floats
    in `[-1, 1)` — deterministic and reproducible
  and free of network calls. Two identical inputs produce identical vectors.

  Configure in `config/test.exs`:

      config :arcana, embedder: {:custom, module: Concept.Knowledge.MockEmbedder}
  """
  @behaviour Arcana.Embedder

  @dim 384

  @impl Arcana.Embedder
  def dimensions(_opts), do: @dim

  @impl Arcana.Embedder
  def embed(text, _opts) when is_binary(text) do
    {:ok, vector_for(text)}
  end

  @impl Arcana.Embedder
  def embed_batch(texts, _opts) when is_list(texts) do
    {:ok, Enum.map(texts, &vector_for/1)}
  end

  defp vector_for(text) do
    seed = :crypto.hash(:sha256, text)

    # Stretch 32 bytes → 768 floats via repeated hashing.
    1..div(@dim, 16)
    |> Enum.reduce({seed, []}, fn _i, {acc, vecs} ->
      next = :crypto.hash(:sha256, acc)
      floats = for <<b::8 <- next>>, do: b / 127.5 - 1.0
      {next, vecs ++ floats}
    end)
    |> elem(1)
    |> Enum.take(@dim)
  end
end
