defmodule ConceptWeb.Components.PresenceBarTest do
  @moduledoc """
  C-2 (G9): the page presence bar renders live collaborators as a coloured
  avatar stack. This data was computed but never rendered before; the contract
  here guards the avatar treatment + that an empty list renders nothing.
  """
  use ConceptWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ConceptWeb.Components.PresenceBar

  defp user(name, color), do: %{id: Ecto.UUID.generate(), display_name: name, color: color}

  test "renders an avatar per collaborator with their colour + initial" do
    users = [user("Ada Lovelace", "#ff0000"), user("Grace Hopper", "#00ff00")]
    html = render_component(&presence_bar/1, %{users: users})

    assert html =~ "Active"
    assert html =~ "background-color: #ff0000"
    assert html =~ "background-color: #00ff00"
    # initial of the display name
    assert html =~ ">A<" or html =~ "A\n"
    assert html =~ ~s(title="Ada Lovelace")
    assert html =~ ~s(title="Grace Hopper")
  end

  test "renders nothing when no collaborators are present" do
    html = render_component(&presence_bar/1, %{users: []})
    refute html =~ "Active"
  end
end
