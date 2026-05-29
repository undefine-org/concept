defmodule Concept.Objects.FieldTypes.Relation do
  @moduledoc """
  A reference to one or more other `Record`s. Unlike every other field type,
  relation values are **not** stored in the `Record.fields` JSONB bag — they
  are first-class `RecordLink` rows (so edges are queryable and `blocked_by`
  readiness can be derived in SQL).

  This module validates only the *shape* of an incoming reference: a uuid or a
  list of uuids. The `Record` engine routes persistence to `RecordLink`.

  `config` shape: `%{"target_object_type_id" => uuid, "many" => true}`.
  """
  @behaviour Concept.Objects.FieldType

  @impl true
  def key, do: :relation

  @impl true
  def label, do: "Relation"

  @impl true
  def relational?, do: true

  @impl true
  def validate(nil, _config), do: :ok

  def validate(value, config) do
    if many?(config) do
      validate_many(value)
    else
      validate_one(value)
    end
  end

  defp validate_one(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, _} -> :ok
      :error -> {:error, "must be a record id (uuid)"}
    end
  end

  defp validate_one(_), do: {:error, "must be a single record id"}

  defp validate_many(value) when is_list(value) do
    if Enum.all?(value, &match?({:ok, _}, Ecto.UUID.cast(&1))),
      do: :ok,
      else: {:error, "must be a list of record ids (uuids)"}
  end

  defp validate_many(_), do: {:error, "must be a list of record ids"}

  @impl true
  def default(config), do: if(many?(config), do: [], else: nil)

  @impl true
  def cast(nil, _config), do: {:ok, nil}

  def cast(value, config) do
    case validate(value, config) do
      :ok -> {:ok, value}
      err -> err
    end
  end

  @impl true
  def json_schema(config) do
    ref = %{"type" => "string", "format" => "uuid"}
    if many?(config), do: %{"type" => "array", "items" => ref}, else: ref
  end

  defp many?(config), do: !!Map.get(config, "many", false)
end
