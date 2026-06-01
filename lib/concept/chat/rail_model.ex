defmodule Concept.Chat.RailModel do
  @moduledoc """
  The **adaptive channel rail** projection — the single source of truth for how
  a flat conversation list becomes the grouped sidebar tree. The structural
  twin of `Concept.Chat.MessageKind`: the rail template dispatches on a derived
  trait (`mode`) rather than branching on `length(conversations)` at render.

  ## The 3-level model (HOST › CONVERSATION › THREAD)

  A conversation is always *about* a **host** (a page, the workspace, later a
  user). `conversations_for_host` returns a **list** — one host has *many*
  conversations. So the rail groups by host and lists conversations under it,
  **adaptively**:

    * a host with **≥ 2** conversations → `:category` — a collapsible host
      header with its conversations indented beneath it;
    * a host with **exactly 1** conversation → `:inline` — the conversation
      renders directly (no two-line header tax), with a muted "in <host>" ref
      revealed on hover;
    * a host with **0** conversations → omitted (nothing to show).

  This keeps the common "one chat about a page" case flat and only pays the
  grouping cost when a host has actually accumulated several topics.

  ## Ordering & sections

  Host groups are ordered by their position in `Concept.Hostable.types()`, so a
  newly-registered Hostable (e.g. `:record`) slots into the rail with **zero**
  template edits — the registry is the source of truth (the block-types ethic
  applied to the sidebar). `section_for/1` maps a host type to a display
  section heading; `glyph/1` gives a **host-native** hero icon (a channel is a
  *place*, not a `#` chatroom).

  Pure and total: takes plain conversation maps/structs, touches no DB. Label
  resolution (page titles) is the caller's concern — kept out so the projection
  stays dependency-free and testable.
  """

  @type mode :: :category | :inline
  @type host_group :: %{
          host_type: atom(),
          host_id: binary() | nil,
          mode: mode(),
          conversations: [map()]
        }

  @doc """
  Group a flat conversation list into ordered host groups with an adaptive
  `mode`. Total: every input conversation appears in exactly one group; counts
  are conserved; groups are ordered by `Hostable.types()`.
  """
  @spec group_by_host([map()]) :: [host_group()]
  def group_by_host(conversations) when is_list(conversations) do
    order = Concept.Hostable.types()

    conversations
    |> Enum.group_by(fn c -> {host_type(c), host_id(c)} end)
    |> Enum.map(fn {{host_type, host_id}, convs} ->
      %{
        host_type: host_type,
        host_id: host_id,
        mode: if(length(convs) >= 2, do: :category, else: :inline),
        conversations: convs
      }
    end)
    |> Enum.sort_by(fn g ->
      # Primary: registry section order (unknown types sink to the end).
      # Secondary: host_id for a stable, deterministic order within a type.
      {Enum.find_index(order, &(&1 == g.host_type)) || length(order), g.host_id || ""}
    end)
  end

  @doc "The display section a host type belongs to in the rail."
  @spec section_for(atom()) :: :workspace | :pages | :direct_messages | :other
  def section_for(:workspace), do: :workspace
  def section_for(:page), do: :pages
  def section_for(:user), do: :direct_messages
  def section_for(_), do: :other

  @doc "A human label for a rail section heading."
  @spec section_label(atom()) :: String.t()
  def section_label(:workspace), do: "Workspace"
  def section_label(:pages), do: "Pages"
  def section_label(:direct_messages), do: "Direct messages"
  def section_label(:other), do: "Other"

  @doc """
  A **host-native** hero icon for a host type — a channel is a *place*, not a
  `#` chatroom (✦ workspace · 📄 page · 👤 user/DM).
  """
  @spec glyph(atom()) :: String.t()
  def glyph(:workspace), do: "hero-sparkles-micro"
  def glyph(:page), do: "hero-document-text-micro"
  def glyph(:user), do: "hero-user-micro"
  def glyph(_), do: "hero-cube-micro"

  # ── shape-tolerant field access (struct- or string-keyed) ────────────────
  defp host_type(%{host_type: t}), do: t
  defp host_type(%{"host_type" => t}), do: t
  defp host_type(_), do: :workspace

  defp host_id(%{host_id: id}), do: id
  defp host_id(%{"host_id" => id}), do: id
  defp host_id(_), do: nil
end
