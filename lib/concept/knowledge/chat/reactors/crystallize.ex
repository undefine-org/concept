defmodule Concept.Knowledge.Chat.Reactors.Crystallize do
  @moduledoc """
  Crystallize a conversation into a durable page (PLAN-010 §20, §46): talk
  becomes document.

  COPY semantics (not move): each block in the conversation's messages is
  *cloned* onto the target page, a provenance `Knowledge.Link` is authored from
  the source message-block to the new page-block, and the conversation is marked
  crystallized. The conversation's scrollback stays intact; the page gains
  durable copies (matches the mockup's "from conversation" provenance chip).

  Cross-resource workflow (Block + Link + Conversation), wrapped as a single
  action per the project convention (AGENTS.md rule 3).
  """
  use Reactor

  input :conversation_id
  input :target_page_id
  input :workspace_id

  step :clone, Concept.Knowledge.Chat.Reactors.Steps.CloneBlocks do
    argument :conversation_id, input(:conversation_id)
    argument :target_page_id, input(:target_page_id)
    argument :workspace_id, input(:workspace_id)
  end

  return :clone
end
