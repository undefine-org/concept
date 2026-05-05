defmodule Concept.Pages.BlockTypes.Code do
  @behaviour Concept.Pages.BlockType
  @languages ~w(plain javascript typescript elixir python ruby html css json markdown sql bash rust go)
  @impl true
  def type, do: :code
  @impl true
  def default_content, do: Concept.Lexical.empty_code()
  @impl true
  def default_props, do: %{"language" => "plain"}
  @impl true
  def validate_props(%{"language" => lang}) when lang in @languages, do: :ok
  def validate_props(_), do: {:error, "language must be one of #{Enum.join(@languages, ",")}"}
  @impl true
  def lexical_node, do: "code"
  @impl true
  def slash_menu,
    do: %{label: "Code", icon: "</>", keywords: ["code", "snippet", "monospace"], group: :media}

  @impl true
  def container?, do: false

  def languages, do: @languages
end
