defmodule Concept.Objects.FieldTypes.Select do
  @moduledoc """
  A single-choice field constrained to a configured option set.

  `config` shape: `%{"options" => ["low", "normal", "high"]}`.
  """
  @behaviour Concept.Objects.FieldType
  use Phoenix.Component

  # Stable palette: option index → chip classes. Deterministic so the same
  # option always gets the same color across renders.
  @palette [
    "bg-notion-gray text-notion-text-light",
    "bg-blue-100 text-blue-800",
    "bg-green-100 text-green-800",
    "bg-yellow-100 text-yellow-800",
    "bg-purple-100 text-purple-800",
    "bg-red-100 text-red-800",
    "bg-pink-100 text-pink-800"
  ]

  @impl true
  def key, do: :select

  @impl true
  def label, do: "Select"

  @impl true
  def icon, do: "◉"

  @impl true
  def validate(nil, _config), do: :ok

  def validate(value, config) when is_binary(value) do
    if value in options(config) do
      :ok
    else
      {:error, "must be one of: #{Enum.join(options(config), ", ")}"}
    end
  end

  def validate(_value, _config), do: {:error, "must be a string option"}

  @impl true
  def default(config), do: Map.get(config, "default")

  @impl true
  def cast(nil, _config), do: {:ok, nil}
  def cast(value, _config) when is_binary(value), do: {:ok, value}
  def cast(value, _config), do: {:ok, to_string(value)}

  @impl true
  def json_schema(config) do
    case options(config) do
      [] -> %{"type" => "string"}
      opts -> %{"type" => "string", "enum" => opts}
    end
  end

  @impl true
  def render_value(value, config, assigns) do
    assigns =
      assigns
      |> assign(:value, value)
      |> assign(:chip, value && chip_class(value, config))

    ~H"""
    <%= if is_binary(@value) and @value != "" do %>
      <span class={["rounded px-1.5 py-0.5 text-xs font-medium", @chip]}>{@value}</span>
    <% else %>
      <span class="text-sm text-notion-text-light">—</span>
    <% end %>
    """
  end

  @impl true
  def render_input(field, config, assigns) do
    assigns =
      assigns
      |> assign(:field, field)
      |> assign(:options, options(config))

    ~H"""
    <select
      id={@field.id}
      name={@field.name}
      class="w-full rounded-md border border-notion-divider px-2 py-1 text-sm"
    >
      <option value="">—</option>
      <option :for={opt <- @options} value={opt} selected={to_string(@field.value) == opt}>
        {opt}
      </option>
    </select>
    """
  end

  @impl true
  def render_config_form(config, form) do
    assigns = %{config: config, form: form, options: options(config)}

    ~H"""
    <div class="space-y-1">
      <label class="text-xs font-medium text-notion-text-light">
        Options (one per line)
      </label>
      <textarea
        name={@form[:options].name}
        rows="4"
        class="w-full rounded-md border border-notion-divider px-2 py-1 text-sm"
      >{Enum.join(@options, "\n")}</textarea>
    </div>
    """
  end

  defp options(config), do: Map.get(config, "options", [])

  defp chip_class(value, config) do
    case Enum.find_index(options(config), &(&1 == value)) do
      nil -> List.first(@palette)
      idx -> Enum.at(@palette, rem(idx, length(@palette)))
    end
  end
end
