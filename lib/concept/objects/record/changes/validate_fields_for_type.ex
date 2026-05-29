defmodule Concept.Objects.Record.Changes.ValidateFieldsForType do
  @moduledoc """
  Cast then validate a record's `fields` JSONB bag against its `ObjectType`'s
  `FieldDef`s.

  The object-layer analogue of `Concept.Pages.Block.Changes.ValidatePropsForType`:
  for each defined field, first `FieldType.cast/2` the raw input (form strings,
  MCP payloads, indexed checklist maps) into the stored representation, then
  dispatch to `FieldType.validate/2`; enforce `required?`; and reject unknown
  keys. Casting here (one place, before validation) means every write source
  — the slide-over form, MCP tools, seeds — normalizes uniformly; a number
  field typed as "3" in a form lands as 3 rather than failing `is_number`.
  Relation fields are skipped here (their values live in `RecordLink` rows).
  """
  use Ash.Resource.Change
  require Ash.Query

  @impl true
  def change(changeset, _opts, _ctx) do
    Ash.Changeset.before_action(changeset, fn cs ->
      tenant = cs.tenant || Ash.Changeset.get_attribute(cs, :workspace_id)
      type_id = Ash.Changeset.get_attribute(cs, :object_type_id)
      fields = Ash.Changeset.get_attribute(cs, :fields) || %{}

      if is_nil(tenant) or is_nil(type_id) do
        cs
      else
        defs = field_defs(type_id, tenant)
        validate(cs, defs, fields)
      end
    end)
  end

  defp validate(cs, defs, fields) do
    defs_by_key = Map.new(defs, &{&1.key, &1})
    known_keys = MapSet.new(Map.keys(defs_by_key))

    case cast_fields(defs, fields) do
      {:ok, cast} ->
        cs
        |> Ash.Changeset.force_change_attribute(:fields, cast)
        |> reject_unknown_keys(cast, known_keys)
        |> validate_each(defs, cast)

      {:error, errors} ->
        Enum.reduce(errors, cs, fn {name, msg}, acc ->
          Ash.Changeset.add_error(acc, field: :fields, message: "#{name}: #{msg}")
        end)
    end
  end

  # Cast each non-relational field's raw value via its FieldType.cast/2,
  # collecting cast failures. Keys with no matching def pass through untouched
  # (reject_unknown_keys reports them).
  defp cast_fields(defs, fields) do
    defs_by_key = Map.new(defs, &{&1.key, &1})

    {cast, errors} =
      Enum.reduce(fields, {%{}, []}, fn {key, value}, {acc, errs} ->
        case Map.get(defs_by_key, key) do
          nil ->
            {Map.put(acc, key, value), errs}

          def ->
            mod = Concept.Objects.FieldTypes.lookup(def.field_type)

            if relational?(mod) do
              {Map.put(acc, key, value), errs}
            else
              case mod.cast(value, def.config || %{}) do
                {:ok, cast_val} -> {Map.put(acc, key, cast_val), errs}
                {:error, msg} -> {acc, [{def.name, msg} | errs]}
              end
            end
        end
      end)

    case errors do
      [] -> {:ok, cast}
      errs -> {:error, Enum.reverse(errs)}
    end
  end

  defp reject_unknown_keys(cs, fields, known_keys) do
    unknown = fields |> Map.keys() |> Enum.reject(&MapSet.member?(known_keys, &1))

    case unknown do
      [] ->
        cs

      keys ->
        Ash.Changeset.add_error(cs,
          field: :fields,
          message: "unknown field(s): #{Enum.join(keys, ", ")}"
        )
    end
  end

  defp validate_each(cs, defs, fields) do
    Enum.reduce(defs, cs, fn def, acc ->
      mod = Concept.Objects.FieldTypes.lookup(def.field_type)
      value = Map.get(fields, def.key)

      cond do
        relational?(mod) ->
          acc

        def.required? and is_nil(value) ->
          Ash.Changeset.add_error(acc, field: :fields, message: "#{def.name} is required")

        true ->
          case mod.validate(value, def.config || %{}) do
            :ok ->
              acc

            {:error, msg} ->
              Ash.Changeset.add_error(acc, field: :fields, message: "#{def.name}: #{msg}")
          end
      end
    end)
  end

  defp relational?(mod), do: function_exported?(mod, :relational?, 0) and mod.relational?()

  defp field_defs(type_id, tenant) do
    Concept.Objects.FieldDef
    |> Ash.Query.filter(object_type_id == ^type_id)
    |> Ash.Query.set_tenant(tenant)
    |> Ash.read!(authorize?: false)
  end
end
