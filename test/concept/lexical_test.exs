defmodule Concept.LexicalTest do
  @moduledoc """
  Focused tests for `Concept.Lexical.to_html/1` link serialization.

  Companion to BUG-031 — verifies the server-side render path for the
  Lexical `link` node shape produced by `@lexical/link` `LinkNode`.
  """
  use ExUnit.Case, async: true

  alias Concept.Lexical

  defp link_doc(url, text) do
    %{
      "root" => %{
        "type" => "root",
        "children" => [
          %{
            "type" => "paragraph",
            "direction" => "ltr",
            "format" => "",
            "indent" => 0,
            "version" => 1,
            "children" => [
              %{
                "type" => "link",
                "url" => url,
                "direction" => "ltr",
                "format" => "",
                "indent" => 0,
                "version" => 1,
                "children" => [
                  %{
                    "type" => "text",
                    "text" => text,
                    "format" => 0,
                    "detail" => 0,
                    "mode" => "normal",
                    "style" => "",
                    "version" => 1
                  }
                ]
              }
            ]
          }
        ],
        "direction" => "ltr",
        "format" => "",
        "indent" => 0,
        "version" => 1
      }
    }
  end

  describe "to_html/1 link serialization" do
    test "renders LinkNode as <a href=\"…\">" do
      html = Lexical.to_html(link_doc("https://example.com", "click me"))

      assert html =~ ~s|<a href="https://example.com"|
      assert html =~ "click me"
      assert html =~ "</a>"
    end

    test "wraps the link inside the paragraph" do
      html = Lexical.to_html(link_doc("https://example.com", "click me"))

      assert html ==
               ~s|<p><a href="https://example.com" rel="noopener" target="_blank">click me</a></p>|
    end

    test "sanitises non http(s)/mailto URLs to '#'" do
      html = Lexical.to_html(link_doc("javascript:alert(1)", "bad"))

      refute html =~ "javascript:"
      assert html =~ ~s|href="#"|
    end

    test "escapes special chars inside link text" do
      html = Lexical.to_html(link_doc("https://example.com", "<script>"))

      refute html =~ "<script>"
      assert html =~ "&lt;script&gt;"
    end

    test "round-trip with bold text inside link" do
      doc = %{
        "root" => %{
          "type" => "root",
          "children" => [
            %{
              "type" => "paragraph",
              "children" => [
                %{
                  "type" => "link",
                  "url" => "https://example.com",
                  "children" => [
                    %{
                      "type" => "text",
                      "text" => "bold link",
                      "format" => 1,
                      "detail" => 0,
                      "mode" => "normal",
                      "style" => "",
                      "version" => 1
                    }
                  ]
                }
              ]
            }
          ]
        }
      }

      html = Lexical.to_html(doc)
      assert html =~ ~s|<a href="https://example.com"|
      assert html =~ "<strong>bold link</strong>"
    end
  end

  describe "to_markdown/1 link serialization" do
    test "renders link as Markdown [text](url)" do
      md = Lexical.to_markdown(link_doc("https://example.com", "click me"))

      assert md =~ "[click me](https://example.com)"
    end
  end
end
