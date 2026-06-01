defmodule Concept.Resources.Changes.TypedJsonb do
  @moduledoc """
  The one genuinely shared seam between the codebase's two typed-JSONB
  validators — `Block.props` (validated against its `BlockType`) and
  `Record.fields` (validated against its `ObjectType`'s `FieldDef`s).

  Their validation *algorithms* legitimately differ and are **not** unified
  here: a Block validates its whole prop map monolithically
  (`BlockType.validate_props/1`); a Record casts then validates each field
  against a runtime set of defs, rejecting unknown keys. Folding those two into
  one engine would be a leaky abstraction (Block never casts; Record writes cast
  values back). What they *do* share — and all this module owns — is the
  **error-reporting contract**: a validation result folded onto a single
  changeset field with one message shape, so a bad block prop and a bad record
  field surface identically to forms and MCP.

  ## Result shape

  A validator yields `:ok` or `{:error, e}` where `e` is one error or a list:

    * `"message"`            — attached verbatim
    * `{nil, "message"}`     — attached verbatim (explicit no-label)
    * `{"Label", "message"}` — attached as `"Label: message"`
  """
  alias Ash.Changeset

  @type error :: String.t() | {label :: String.t() | nil, message :: String.t()}

  @doc """
  Fold a validation result onto `field`. `:ok` is a no-op; `{:error, errors}`
  attaches one changeset error per entry, normalizing `{label, message}` pairs
  to a single `"label: message"` shape.
  """
  @spec put_result(Changeset.t(), atom(), :ok | {:error, error() | [error()]}) :: Changeset.t()
  def put_result(changeset, _field, :ok), do: changeset

  def put_result(changeset, field, {:error, errors}) do
    Enum.reduce(List.wrap(errors), changeset, &add(&2, field, &1))
  end

  defp add(cs, field, {nil, message}), do: error(cs, field, message)
  defp add(cs, field, {label, message}), do: error(cs, field, "#{label}: #{message}")
  defp add(cs, field, message) when is_binary(message), do: error(cs, field, message)

  defp error(cs, field, message), do: Changeset.add_error(cs, field: field, message: message)
end
