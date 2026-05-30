defmodule Concept.Objects.FieldTypes.User do
  @moduledoc """
  A reference to a workspace `User` (human or agent), stored as a uuid string
  in the record's `fields` bag.

  Membership validity is enforced at the resource layer (the actor/tenant
  context); this type validates only that the value is a uuid.

  Render fns expect an ambient `:members` assign — a list of
  `%{id, email}` (or `%Concept.Accounts.User{}`) — so the component resolves a
  uuid to a display name + avatar without a DB call inside render.
  """
  @behaviour Concept.Objects.FieldType
  use Phoenix.Component

  @impl true
  def key, do: :user

  @impl true
  def label, do: "User"

  @impl true
  def icon, do: "👤"

  @impl true
  def validate(nil, _config), do: :ok

  def validate(value, _config) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, _} -> :ok
      :error -> {:error, "must be a user id (uuid)"}
    end
  end

  def validate(_value, _config), do: {:error, "must be a user id (uuid)"}

  @impl true
  def default(_config), do: nil

  @impl true
  def cast(nil, _config), do: {:ok, nil}

  def cast(value, _config) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, "is not a valid user id"}
    end
  end

  def cast(_value, _config), do: {:error, "is not a valid user id"}

  @impl true
  def json_schema(_config), do: %{"type" => "string", "format" => "uuid"}

  @impl true
  def render_value(value, _config, assigns) do
    member = find_member(Map.get(assigns, :members, []), value)

    assigns =
      assigns
      |> assign(:member, member)
      |> assign(:name, member && member_name(member))
      |> assign(:initial, member && initial(member_name(member)))
      |> assign(:is_agent, member && member_role(member) == :agent)

    ~H"""
    <%= if @member do %>
      <span class="inline-flex items-center gap-1.5">
        <span class="flex h-5 w-5 items-center justify-center rounded-full bg-notion-text text-[10px] font-medium text-white">
          {@initial}
        </span>
        <span class="text-sm text-notion-text">{@name}</span>
        <%= if @is_agent do %>
          <span class="inline-flex items-center rounded bg-blue-50 px-1.5 py-0.5 text-[10px] font-medium text-blue-600">
            🤖 agent
          </span>
        <% end %>
      </span>
    <% else %>
      <span class="text-sm text-notion-text-light">Unassigned</span>
    <% end %>
    """
  end

  @impl true
  def render_input(field, _config, assigns) do
    members = Map.get(assigns, :members, [])
    assigns = assigns |> assign(:field, field) |> assign(:members, members)

    ~H"""
    <select
      id={@field.id}
      name={@field.name}
      class="w-full rounded-md border border-notion-divider px-2 py-1 text-sm"
    >
      <option value="">Unassigned</option>
      <option
        :for={m <- @members}
        value={member_id(m)}
        selected={to_string(@field.value) == member_id(m)}
      >
        {member_name(m)}
      </option>
    </select>
    """
  end

  @doc "Avatar chip component for a member — `<.avatar member={m} />`."
  attr :member, :map, required: true

  def avatar(assigns) do
    assigns =
      assigns
      |> assign(:name, member_name(assigns.member))
      |> assign(:initial, initial(member_name(assigns.member)))
      |> assign(:is_agent, member_role(assigns.member) == :agent)

    ~H"""
    <span class="inline-flex items-center gap-1.5">
      <span class="flex h-5 w-5 items-center justify-center rounded-full bg-notion-text text-[10px] font-medium text-white">
        {@initial}
      </span>
      <span class="text-sm text-notion-text">{@name}</span>
      <%= if @is_agent do %>
        <span class="inline-flex items-center rounded bg-blue-50 px-1.5 py-0.5 text-[10px] font-medium text-blue-600">
          🤖 agent
        </span>
      <% end %>
    </span>
    """
  end

  defp find_member(_members, nil), do: nil

  defp find_member(members, id) do
    Enum.find(members, fn m -> member_id(m) == to_string(id) end)
  end

  defp member_id(%{id: id}), do: to_string(id)
  defp member_id(%{"id" => id}), do: to_string(id)
  defp member_id(_), do: ""

  defp member_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp member_name(%{email: email}) when not is_nil(email), do: name_from_email(email)
  defp member_name(%{"email" => email}) when not is_nil(email), do: name_from_email(email)
  defp member_name(_), do: "Member"

  # email may be a binary or an Ash.CiString; normalize via to_string/1.
  defp name_from_email(email), do: email |> to_string() |> String.split("@") |> List.first()

  defp initial(name) do
    name |> String.trim() |> String.first() |> Kernel.||("?") |> String.upcase()
  end

  defp member_role(%{role: :agent}), do: :agent
  defp member_role(%{role: "agent"}), do: :agent
  defp member_role(%{"role" => "agent"}), do: :agent
  defp member_role(%{"role" => :agent}), do: :agent
  defp member_role(_), do: nil
end
