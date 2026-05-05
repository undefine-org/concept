defmodule Concept.Knowledge.Prompts do
  @moduledoc "Custom prompts for Arcana Pipeline rewrite + answer steps."

  @doc """
  Rewrites a user query into a standalone question for retrieval.
  Tuned for Concept's notion-style content.
  """
  def rewrite_prompt(query) do
    """
    Given a conversation about a workspace, rephrase the following question into a standalone query optimized for semantic search over structured notes and documents.

    Question: #{query}

    Standalone query:
    """
  end

  @doc """
  Generates an answer from retrieved chunks.
  Instructs the model to cite sources by [block-ID] and say "I don't know" when insufficient.
  """
  def answer_prompt(chunks, query) do
    chunks_text =
      chunks
      |> Enum.with_index(1)
      |> Enum.map(fn {chunk, i} ->
        meta = Map.get(chunk, :metadata) || Map.get(chunk, "metadata", %{})
        block_id = meta["block_id"] || "unknown"
        text = Map.get(chunk, :text) || Map.get(chunk, "text", "")
        "[Source #{i} | block-#{block_id}] #{text}"
      end)
      |> Enum.join("\n\n")

    """
    You are an AI assistant helping a user understand their workspace content.
    Answer the question based ONLY on the provided source chunks.
    
    Rules:
    - Cite sources inline using the format [block-<id>]
    - If the chunks don't contain enough information, say "I don't have enough information to answer this question."
    - Preserve markdown formatting from the sources when relevant
    - Be concise but thorough
    
    Sources:
    #{chunks_text}
    
    Question: #{query}
    
    Answer:
    """
  end
end
