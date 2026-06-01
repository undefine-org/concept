defmodule ConceptWeb.Components.StatePrimitivesTest do
  @moduledoc """
  Contract for the design-system state primitives (Category A). These guard the
  *shape* (markup + a11y) so every consuming surface inherits a consistent,
  accessible loading/empty/error treatment.
  """
  use ConceptWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import ConceptWeb.CoreComponents

  describe "button :loading" do
    test "idle button has no spinner and is enabled" do
      html = render_component(&button/1, %{loading: false, inner_block: slot("Save")})
      assert html =~ "ora-btn"
      assert html =~ ~s(aria-busy="false")
      refute html =~ "ora-spinner"
      refute html =~ "disabled"
    end

    test "loading button is disabled, aria-busy, and shows a spinner" do
      html = render_component(&button/1, %{loading: true, inner_block: slot("Save")})
      assert html =~ ~s(aria-busy="true")
      assert html =~ "ora-spinner"
      assert html =~ "disabled"
      # label is still present (dimmed via CSS, not removed)
      assert html =~ "Save"
      assert html =~ "ora-btn__label"
    end
  end

  describe "skeleton" do
    test "renders N shimmer lines inside an aria-busy status region" do
      html = render_component(&skeleton/1, %{rows: 5})
      assert html =~ ~s(role="status")
      assert html =~ ~s(aria-busy="true")
      assert count(html, "ora-skeleton-line") == 5
      assert html =~ "sr-only"
    end

    test "defaults to 3 rows" do
      html = render_component(&skeleton/1, %{})
      assert count(html, "ora-skeleton-line") == 3
    end
  end

  describe "spinner" do
    test "decorative by default (aria-hidden, no role)" do
      html = render_component(&spinner/1, %{})
      assert html =~ "ora-spinner"
      assert html =~ ~s(aria-hidden="true")
      refute html =~ ~s(role="status")
    end

    test "labelled spinner exposes an accessible status" do
      html = render_component(&spinner/1, %{label: "Saving…"})
      assert html =~ ~s(role="status")
      assert html =~ ~s(aria-label="Saving…")
    end
  end

  describe "empty_state" do
    test "renders icon, title, description, and CTA slot" do
      html =
        render_component(&empty_state/1, %{
          icon: "🗂️",
          title: "No tasks yet",
          inner_block: slot("Create your first task."),
          cta: slot("New task")
        })

      assert html =~ "ora-empty"
      assert html =~ ~s(role="status")
      assert html =~ "No tasks yet"
      assert html =~ "Create your first task."
      assert html =~ "ora-empty__cta"
      assert html =~ "New task"
      assert html =~ ~s(aria-hidden="true")
    end

    test "title-only is valid (no description, no cta)" do
      html = render_component(&empty_state/1, %{title: "Nothing here"})
      assert html =~ "Nothing here"
      refute html =~ "ora-empty__cta"
      refute html =~ "ora-empty__desc"
    end
  end

  describe "error_card" do
    test "is an alert with a warning icon and message, no raw payload" do
      html =
        render_component(&error_card/1, %{
          inner_block: slot("I couldn't search the workspace just now."),
          actions: slot("Retry")
        })

      assert html =~ "ora-error-card"
      assert html =~ ~s(role="alert")
      assert html =~ "hero-exclamation-triangle-mini"
      # (apostrophe is HTML-escaped to &#39; — assert the stable tail)
      assert html =~ "search the workspace just now."
      assert html =~ "ora-error-card__actions"
      assert html =~ "Retry"
    end
  end

  describe "modal" do
    test "is a focus-trapped dialog with aria-modal, esc + overlay cancel" do
      html =
        render_component(&modal/1, %{
          id: "picker",
          title: slot("Link a record"),
          inner_block: slot("body")
        })

      assert html =~ ~s(role="dialog")
      assert html =~ ~s(aria-modal="true")
      assert html =~ ~s(phx-hook="FocusTrap")
      assert html =~ ~s(phx-key="escape")
      assert html =~ "ora-modal-overlay"
      assert html =~ ~s(aria-labelledby="picker-title")
      assert html =~ "Link a record"
      assert html =~ ~s(aria-label="Close")
      assert html =~ "body"
    end
  end

  # Lightweight slot helper for render_component/2.
  defp slot(text), do: [%{inner_block: fn _, _ -> text end}]
  defp count(html, needle), do: html |> String.split(needle) |> length() |> Kernel.-(1)
end
