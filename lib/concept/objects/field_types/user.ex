defmodule Concept.Objects.FieldTypes.User do
  @moduledoc """
  A reference to a workspace `User` (human or agent), stored as a uuid string
  in the record's `fields` bag.

  Membership validity is enforced at the resource layer (the actor/tenant
  context); this type validates only that the value is a uuid.
  """
  @behaviour Concept.Objects.FieldType

  @impl true
  def key, do: :user

  @impl true
  def label, do: "User"

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
end
