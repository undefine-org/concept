defmodule Concept.Pages.BlockTypes.Code do
  use Concept.Pages.BlockType.Text

  @languages ~w(plain javascript typescript elixir python ruby html css json markdown sql bash rust go)
  @impl Concept.Pages.BlockType
  def type, do: :code
  @impl Concept.Pages.BlockType
  def default_content, do: Concept.Lexical.empty_code()
  @impl Concept.Pages.BlockType
  def default_props, do: %{"language" => "plain"}
  @impl Concept.Pages.BlockType
  def validate_props(%{"language" => lang}) when lang in @languages, do: :ok
  def validate_props(_), do: {:error, "language must be one of #{Enum.join(@languages, ",")}"}
  @impl Concept.Pages.BlockType
  def lexical_node, do: "code"
  @impl Concept.Pages.BlockType
  def slash_menu,
    do: %{label: "Code", icon: "</>", keywords: ["code", "snippet", "monospace"], group: :media}

  @impl Concept.Pages.BlockType
  def placeholder, do: "Code"

  def languages, do: @languages
end
