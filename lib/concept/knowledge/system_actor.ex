defmodule Concept.Knowledge.SystemActor do
  @moduledoc "Actor struct for system-context calls bypassing member policies."

  defstruct system?: true, id: "00000000-0000-0000-0000-000000000000"
end
