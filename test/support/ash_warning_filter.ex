defmodule Concept.Test.AshWarningFilter do
  @moduledoc """
  Logger handler that treats specific Ash warnings as fatal during tests.

  ## Why

  Ash 3.x silently *ignores* certain misuses while logging a warning. The
  most common one is calling `Ash.Changeset.set_argument/3` (or
  `change_attribute/3`) **after** `for_create/3` / `for_update/3`:

      [warning] Changeset has already been validated for action :create.
      For safety, we prevent any changes after that point because they
      will bypass validations or other action logic.

  In production this silently drops the argument; in tests it silently
  drops the argument and the test moves on to fail mysteriously later.
  This handler converts those warnings into hard test failures with a
  stack trace pointing at the offending pipeline.

  ## Patterns guarded

  * `Changeset has already been validated for action`
  * `set_argument after for_create`
  * `change_attribute after for_create`

  Patterns can be extended via `@fatal_patterns` below. Keep the list short
  and specific to avoid masking unrelated warnings.

  ## Wiring

  Loaded from `test_helper.exs`:

      Concept.Test.AshWarningFilter.attach()
  """

  @fatal_patterns [
    "Changeset has already been validated for action",
    "set_argument after for_create",
    "change_attribute after for_create"
  ]

  @handler_id :ash_warning_fatal

  @doc """
  Install the handler. Idempotent.
  """
  def attach do
    :ok =
      case :logger.add_handler(@handler_id, __MODULE__, %{level: :warning}) do
        :ok -> :ok
        {:error, {:already_exists, _}} -> :ok
        other -> other
      end
  end

  @doc """
  Remove the handler. Useful for tests that intentionally exercise the
  warning paths.
  """
  def detach do
    _ = :logger.remove_handler(@handler_id)
    :ok
  end

  # ---------------------------------------------------------------------------
  # :logger handler callbacks
  # ---------------------------------------------------------------------------

  @doc false
  def log(%{level: :warning, msg: msg} = _event, _config) do
    text = msg_to_text(msg)

    if Enum.any?(@fatal_patterns, &String.contains?(text, &1)) do
      raise """
      Forbidden Ash warning emitted during test:

          #{String.trim(text)}

      This warning indicates a silent Ash misuse \u2014 the offending change is
      dropped on the floor and the action proceeds without it. See
      `Concept.Test.AshWarningFilter` for the list of fatal patterns and
      `lib/concept/pages/block/changes/evaluate_ai.ex` for an example fix
      (set_argument *before* for_create).
      """
    end

    :ok
  end

  def log(_event, _config), do: :ok

  defp msg_to_text({:string, str}) when is_binary(str), do: str
  defp msg_to_text({:string, iodata}), do: IO.iodata_to_binary(iodata)
  defp msg_to_text({:report, %{} = report}), do: inspect(report)
  defp msg_to_text({:report, kw}) when is_list(kw), do: inspect(kw)

  defp msg_to_text({fmt, args}) when is_list(fmt) or is_binary(fmt) do
    fmt |> :io_lib.format(args) |> IO.iodata_to_binary()
  rescue
    _ -> inspect({fmt, args})
  end

  defp msg_to_text(other), do: inspect(other)
end
