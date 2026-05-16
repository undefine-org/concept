defmodule Concept.Knowledge.ProfileDsl do
  @moduledoc """
  Spark DSL extension declaring compile-time retrieval+generation profiles.

  See `Concept.Knowledge.Profiles` for the concrete declarations and
  `Concept.Knowledge.Profile` for the resulting struct shape.

  Profile model strings are validated against the Gemini family regex at
  compile time; opt out for dev by setting `CONCEPT_ALLOW_ANY_LLM=1`.
  """

  @gemini_model_regex ~r/^google:(gemini-[\d.]+(-flash|-pro|-flash-lite)?(-preview)?|gemini-embedding-[12])(-[\w.]+)?$/

  @profile %Spark.Dsl.Entity{
    name: :profile,
    target: Concept.Knowledge.Profile,
    args: [:name],
    describe: "A named retrieval+generation profile.",
    schema: [
      name:        [type: :atom, required: true],
      description: [type: :string, default: ""],
      rewrite:     [type: :boolean, default: false],
      search:      [type: :keyword_list, default: [mode: :hybrid, limit: 10]],
      rerank:      [type: :boolean, default: false],
      answer:      [type: :keyword_list, required: true],
      ground:      [type: :boolean, default: false],
      tools:       [type: {:list, :atom}, default: []],
      loop?:       [type: :boolean, default: false]
    ],
    transform: {__MODULE__, :transform_entity, []}
  }

  @section %Spark.Dsl.Section{
    name: :profiles,
    entities: [@profile]
  }

  use Spark.Dsl.Extension, sections: [@section]

  @doc false
  def transform_entity(%Concept.Knowledge.Profile{} = profile) do
    profile = normalize_struct(profile)

    case profile.answer[:model] do
      nil ->
        {:error, "profile #{inspect(profile.name)}: missing `answer model:`"}

      model ->
        if allowed_model?(model) do
          {:ok, profile}
        else
          {:error,
           "profile #{inspect(profile.name)}: model #{inspect(model)} is not a Gemini-family " <>
             "model. Allowed pattern: #{inspect(Regex.source(@gemini_model_regex))}. " <>
             "Set CONCEPT_ALLOW_ANY_LLM=1 to override (dev only)."}
        end
    end
  end

  # Spark stuffs the entity's positional args into the schema's matching keys, then
  # builds the target struct from the schema. But `rewrite`/`rerank`/`ground`/`loop?` in
  # the schema map to struct keys `rewrite?`/`rerank?`/`ground?`/`loop?` respectively.
  defp normalize_struct(%Concept.Knowledge.Profile{} = p) do
    schema_extras = %{
      rewrite?: Map.get(p, :rewrite, p.rewrite?),
      rerank?:  Map.get(p, :rerank,  p.rerank?),
      ground?:  Map.get(p, :ground,  p.ground?)
    }

    struct(p, schema_extras)
  end

  defp allowed_model?(model) when is_binary(model) do
    System.get_env("CONCEPT_ALLOW_ANY_LLM") == "1" or Regex.match?(@gemini_model_regex, model)
  end

  defp allowed_model?(_), do: false
end
