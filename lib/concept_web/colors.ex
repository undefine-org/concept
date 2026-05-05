defmodule ConceptWeb.Colors do
  @moduledoc "Deterministic color palette for user presence indicators."

  def palette do
    [
      "#EB5757",
      "#F2994A",
      "#F2C94C",
      "#27AE60",
      "#2F80ED",
      "#9B51E0",
      "#FD79A8",
      "#7F8C8D"
    ]
  end

  def for_user_id(id) do
    palette() |> Enum.at(:erlang.phash2(id, 8))
  end
end
