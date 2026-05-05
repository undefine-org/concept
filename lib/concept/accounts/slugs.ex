defmodule Concept.Accounts.Slugs do
  @moduledoc "Slug derivation: email local-part → URL-safe slug + random suffix."

  @alphabet ~c"abcdefghijklmnopqrstuvwxyz0123456789"

  @doc "Derive `<local>-<6chars>` slug from an email."
  def from_email(email) when is_binary(email) do
    local =
      email
      |> String.downcase()
      |> String.split("@")
      |> hd()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 32)

    "#{local}-#{random_suffix(6)}"
  end

  defp random_suffix(n) do
    1..n
    |> Enum.map(fn _ -> Enum.random(@alphabet) end)
    |> List.to_string()
  end
end
