defmodule Concept.Objects.Guards.RequiresProof do
  @moduledoc """
  Blocks a transition unless a designated field is present and non-empty —
  the "proof of work" gate (e.g. a PR url before `→ review`).

  `config`: `%{"field" => "pr_url"}`.
  """
  @behaviour Concept.Objects.Guard

  @impl true
  def kind, do: :requires_proof

  @impl true
  def label, do: "Requires proof"

  @impl true
  def check(record, config, _ctx) do
    field = Map.get(config, "field")

    cond do
      is_nil(field) ->
        {:error, "requires_proof guard misconfigured: no field"}

      present?(Map.get(record.fields || %{}, field)) ->
        :ok

      true ->
        {:error, "proof required: '#{field}' must be provided"}
    end
  end

  @impl true
  def describe(config) do
    "requires proof in '#{Map.get(config, "field", "?")}'"
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?([]), do: false
  defp present?(_), do: true
end
