defmodule Concept.Lexical do
  @moduledoc """
  Server-side helpers for the Lexical EditorState JSON shape used by `<ora-block>`.

  Format bitmask (matches `@lexical/utils` constants):
    1=BOLD, 2=ITALIC, 4=STRIKETHROUGH, 8=UNDERLINE, 16=CODE
  """

  @bold 1
  @italic 2
  @strike 4
  @underline 8
  @code 16

  def empty_paragraph, do: empty_node("paragraph")
  def empty_heading(level) when level in 1..3, do: empty_node("heading", %{"tag" => "h#{level}"})
  def empty_quote, do: empty_node("quote")
  def empty_code, do: empty_node("code")

  def from_plain_text(text, type \\ "paragraph") when is_binary(text) do
    text_node = %{
      "type" => "text",
      "text" => text,
      "format" => 0,
      "detail" => 0,
      "mode" => "normal",
      "style" => "",
      "version" => 1
    }

    base_node(type, [text_node])
  end

  defp empty_node(type, extra \\ %{}) do
    base_node(type, [], extra)
  end

  defp base_node(type, children, extra \\ %{}) do
    node =
      Map.merge(
        %{
          "type" => type,
          "children" => children,
          "direction" => "ltr",
          "format" => "",
          "indent" => 0,
          "version" => 1
        },
        extra
      )

    %{
      "root" => %{
        "type" => "root",
        "children" => [node],
        "direction" => "ltr",
        "format" => "",
        "indent" => 0,
        "version" => 1
      }
    }
  end

  @doc "Walk a Lexical EditorState extracting concatenated plain text."
  def plain_text(%{"root" => root}), do: walk_text(root)
  def plain_text(_), do: ""

  defp walk_text(%{"children" => children}), do: Enum.map_join(children, "", &walk_text/1)
  defp walk_text(%{"text" => text}), do: text
  defp walk_text(_), do: ""

  @doc "Render Lexical state to safe HTML for SSR fallback. Marks → tags, links → <a>."
  def to_html(%{"root" => root}), do: render_node(root) |> IO.iodata_to_binary()
  def to_html(_), do: ""

  defp render_node(%{"type" => "root", "children" => children}) do
    Enum.map(children, &render_node/1)
  end

  defp render_node(%{"type" => "paragraph", "children" => children}) do
    ["<p>", Enum.map(children, &render_node/1), "</p>"]
  end

  defp render_node(%{"type" => "heading", "tag" => tag, "children" => children}) do
    [~s|<#{tag}>|, Enum.map(children, &render_node/1), ~s|</#{tag}>|]
  end

  defp render_node(%{"type" => "quote", "children" => children}) do
    ["<blockquote>", Enum.map(children, &render_node/1), "</blockquote>"]
  end

  defp render_node(%{"type" => "code", "children" => children}) do
    ["<pre><code>", Enum.map(children, &render_node/1), "</code></pre>"]
  end

  defp render_node(%{"type" => "link", "url" => url, "children" => children}) do
    safe_url = sanitize_url(url)

    [
      ~s|<a href="#{safe_url}" rel="noopener" target="_blank">|,
      Enum.map(children, &render_node/1),
      "</a>"
    ]
  end

  defp render_node(%{"type" => "linebreak"}), do: "<br/>"

  defp render_node(%{"type" => "text", "text" => text} = node) do
    fmt = Map.get(node, "format", 0)
    apply_format(text, fmt)
  end

  defp render_node(%{"children" => children}), do: Enum.map(children, &render_node/1)
  defp render_node(_), do: []

  defp apply_format(text, fmt) do
    safe = escape(text)

    safe
    |> wrap_if(@code, "<code>", "</code>", fmt)
    |> wrap_if(@bold, "<strong>", "</strong>", fmt)
    |> wrap_if(@italic, "<em>", "</em>", fmt)
    |> wrap_if(@underline, "<u>", "</u>", fmt)
    |> wrap_if(@strike, "<s>", "</s>", fmt)
  end

  defp wrap_if(content, bit, open, close, fmt) when bit |> Bitwise.band(fmt) != 0,
    do: [open, content, close]

  defp wrap_if(content, _bit, _open, _close, _fmt), do: content

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp sanitize_url(url) when is_binary(url) do
    cond do
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://") or
          String.starts_with?(url, "mailto:") ->
        escape(url)

      true ->
        "#"
    end
  end

  defp sanitize_url(_), do: "#"
end
