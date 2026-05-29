defmodule ConceptWeb.Objects.WorkflowEditorComponent do
  @moduledoc """
  Workflow editor embedded in the object-type editor: manage the type's
  lifecycle — states (each mapped to a fixed category) and the guarded
  transitions between them (list-first; a drag canvas is a tracked FUP).

  Fleshed out in wave E2. This shell renders the section frame so the type
  editor compiles and the workflow surface has a stable mount point.

  LiveView purity (EX9001): all access via `Concept.Objects` code-interface.
  """
  use ConceptWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="mb-8">
      <h2 class="mb-3 text-sm font-semibold uppercase tracking-wide text-notion-text-light">
        Workflow
      </h2>
      <p class="text-sm text-notion-text-light">Workflow editing coming in this view.</p>
    </section>
    """
  end
end
