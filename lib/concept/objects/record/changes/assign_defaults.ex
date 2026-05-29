defmodule Concept.Objects.Record.Changes.AssignDefaults do
  @moduledoc """
  Fill a new record's `fields` with each `FieldDef`'s default (for keys not
  supplied), and derive `title` from the type's designated title field.
  """
  use Ash.Resource.Change
  require Ash.Query

  @impl true
  def change(changeset, _opts, _ctx) do
    Ash.Changeset.before_action(changeset, fn cs ->
      tenant = cs.tenant || Ash.Changeset.get_attribute(cs, :workspace_id)
      type_id = Ash.Changeset.get_attribute(cs, :object_type_id)

      if is_nil(tenant) or is_nil(type_id) do
        cs
      else
        defs = field_defs(type_id, tenant)
        given = Ash.Changeset.get_attribute(cs, :fields) || %{}

        merged =
          Enum.reduce(defs, given, fn def, acc ->
            if Map.has_key?(acc, def.key) do
              acc
            else
              mod = Concept.Objects.FieldTypes.lookup(def.field_type)
              default = mod.default(def.config || %{})
              if is_nil(default), do: acc, else: Map.put(acc, def.key, default)
            end
          end)

        cs
        |> Ash.Changeset.force_change_attribute(:fields, merged)
        |> maybe_set_title(defs, merged)
      end
    end)
  end

  defp maybe_set_title(cs, defs, fields) do
    existing = Ash.Changeset.get_attribute(cs, :title)

    if is_binary(existing) and existing != "" do
      cs
    else
      case Enum.find(defs, & &1.is_title?) do
        %{key: key} ->
          title = fields[key]
          if is_binary(title), do: Ash.Changeset.force_change_attribute(cs, :title, title), else: cs

        _ ->
          cs
      end
    end
  end

  defp field_defs(type_id, tenant) do
    Concept.Objects.FieldDef
    |> Ash.Query.filter(object_type_id == ^type_id)
    |> Ash.Query.set_tenant(tenant)
    |> Ash.read!(authorize?: false)
  end
end
