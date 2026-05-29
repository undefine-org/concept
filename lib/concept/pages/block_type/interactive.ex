defmodule Concept.Pages.BlockType.Interactive do
  @moduledoc """
  `use`-able mixin that turns a `Concept.Pages.BlockType` module into a
  `Phoenix.LiveComponent`.

  ## Why

  Interactive blocks have four wiring touchpoints that historically had to be
  hand-wired in four files: the block-type module, `block_render.ex`, a JS
  hook, and a LiveView `handle_event/3` clause. This macro collapses all of
  them into a single declaration:

      defmodule Concept.Pages.BlockTypes.AiAnswer do
        use Concept.Pages.BlockType.Interactive,
          ash_actions: [
            evaluate: [Concept.Pages, :evaluate_ai, [:prompt, :scope, :profile]],
            refresh:  [Concept.Pages, :evaluate_ai, [:prompt, :scope, :profile]],
            retry:    [Concept.Pages, :evaluate_ai, [:prompt, :scope, :profile]]
          ]

  Each value is `[Module, :fun, [arg_atom, ...]]`. Generated `handle_event/3`
  calls `Module.fun(block, arg1, arg2, ..., actor: ..., tenant: ...)` where
  each `argN` is pulled from the event payload by atom-or-string key.

        @impl true
        def type, do: :ai_answer
        @impl true
        def lexical_node, do: "ai-answer"
        @impl true
        def slash_menu, do: %{label: "AI Answer", icon: "✨", keywords: ~w(ai), group: :ai}

        @impl true
        def update(assigns, socket) do
          # derive @state, @preview_html, @message_id, @staleness_attrs from
          # assigns.block, then:
          {:ok, assign(socket, assigns)}
        end

        @impl true
        def render_body(assigns) do
          ~H"\""
          <ora-ai-block block-id={@block.id} state={@state} ... />
          "\""
        end
      end

  ## What it guarantees

  * The rendered element always wraps `render_body/1` in a `<div>` with
    `phx-hook="OraBlock"`, `phx-update="ignore"`, `phx-target={@myself}`,
    `data-block-id`, and `data-events="…"` matching the `ash_actions` keys —
    by construction. The user cannot forget any of them.
  * `handle_event/3` clauses are generated, one per `ash_actions` entry, and
    invoke the declared Ash code interface with the named arguments lifted
    from the event payload, `actor: socket.assigns.current_user`, and
    `tenant: block.workspace_id`.
  * `render_kind/0` returns `:interactive` so the dispatcher routes through
    `<.live_component ...>`.

  ## Contract on the consuming module

  * Must define `render_body/1` (compile-time enforced via `@before_compile`).
  * Should define `update/2` to derive state from `assigns.block`.
  """

  @doc """
  Invoked from generated `handle_event/3` clauses. Resolves the named args
  from the event payload, calls the declared Ash code interface, and returns
  the call's result for the caller to inspect or ignore. Public so generated
  code can dispatch into a single helper rather than inline anonymous logic.

  Enforces the **actor contract** for Interactive blocks: `current_user`
  must be a struct (typically `Concept.Accounts.User`) so downstream Ash
  actions can resolve `relate_actor/1` and policies that read
  `actor.__struct__`. Bare maps and `nil` raise immediately with a clear
  pointer at the LC mounting code, rather than producing the cryptic
  "could not relate to actor" deep in the Ash pipeline.
  """
  def invoke_action({mod, fun, arg_atoms}, payload, socket) do
    block = socket.assigns.block
    actor = require_actor!(socket.assigns[:current_user])
    tenant = block.workspace_id

    args =
      Enum.map(arg_atoms, fn key ->
        Map.get(payload, Atom.to_string(key)) || Map.get(payload, key)
      end)

    apply(mod, fun, [block | args] ++ [[actor: actor, tenant: tenant]])
  end

  @doc false
  # The actor must be either:
  #   * a struct (regular user actor; Ash uses __struct__ for relate_actor),
  #   * or `%{system?: true}` (internal escalation; matched by lock-bypass
  #     changes like `Concept.Pages.Block.Changes.RequireOwnLock`).
  def require_actor!(%_struct{} = actor), do: actor
  def require_actor!(%{system?: true} = actor), do: actor

  def require_actor!(other) do
    raise ArgumentError, """
    Interactive block LiveComponent received an invalid `current_user` assign.

    Expected: a struct (e.g. `%Concept.Accounts.User{}`) or `%{system?: true}`.
    Got:      #{inspect(other)}

    The LC's parent LiveView must propagate a real `Concept.Accounts.User`
    struct — a bare map like
    `%{id: user_id, email: ...}` won't satisfy `relate_actor/1` on resources
    that hold a `belongs_to :user` relationship.

    Symptom of misuse: "could not relate to actor" deep inside an Ash
    changeset, e.g. when `Concept.Knowledge.Chat.Conversation.create` runs
    via the `:respond` AshOban trigger.

    Fix: in the parent LiveView's `mount/3`, load the User by id:

        case Ash.get(Concept.Accounts.User, user_id, authorize?: false) do
          {:ok, user} -> assign(socket, :current_user, user)
          _ -> ...
        end

    See `lib/concept_web/live/page_editor_live.ex` for a reference.
    """
  end

  defmacro __using__(opts) do
    ash_actions = Keyword.get(opts, :ash_actions, [])
    mcp_opts = Keyword.get(opts, :mcp, [])

    unless is_list(ash_actions) and ash_actions != [] do
      raise CompileError,
        description:
          "use Concept.Pages.BlockType.Interactive requires non-empty `:ash_actions` keyword list"
    end

    verbs = Enum.map(ash_actions, fn {verb, _} -> verb end)
    data_events_str = verbs |> Enum.map(&Atom.to_string/1) |> Enum.join(" ")

    # MCP exposure metadata kept in module attributes so __block_type_mcp_tools__/0
    # (generated via @before_compile) can build %AshAi.Tool{} entries that the
    # Concept.Pages AutoTools transformer picks up at domain-compile time.
    mcp_ash_actions = normalize_mcp_ash_actions(ash_actions)
    mcp_descriptions = Keyword.get(mcp_opts, :descriptions, [])
    mcp_only = Keyword.get(mcp_opts, :only)
    mcp_except = Keyword.get(mcp_opts, :except, [])

    event_clauses =
      for {verb, mfa} <- ash_actions do
        [mod_ast, fun_ast, arg_atoms] = unwrap_mfa(mfa)
        verb_str = Atom.to_string(verb)

        quote do
          @impl Phoenix.LiveComponent
          def handle_event(unquote(verb_str), payload, socket) do
            Concept.Pages.BlockType.Interactive.invoke_action(
              {unquote(mod_ast), unquote(fun_ast), unquote(arg_atoms)},
              payload,
              socket
            )

            {:noreply, socket}
          end
        end
      end

    quote do
      use Phoenix.LiveComponent
      @behaviour Concept.Pages.BlockType
      @before_compile Concept.Pages.BlockType.Interactive

      # Use `unquote` (not Macro.escape) so `__aliases__` AST nodes resolve
      # to actual module atoms in the consuming module's __ENV__ context.
      @__block_type_mcp_ash_actions__ unquote(mcp_ash_actions)
      @__block_type_mcp_descriptions__ unquote(mcp_descriptions)
      @__block_type_mcp_only__ unquote(mcp_only)
      @__block_type_mcp_except__ unquote(mcp_except)

      @impl Concept.Pages.BlockType
      def render_kind, do: :interactive

      @impl Concept.Pages.BlockType
      def default_content, do: %{}
      @impl Concept.Pages.BlockType
      def default_props, do: %{}
      @impl Concept.Pages.BlockType
      def validate_props(_), do: :ok
      @impl Concept.Pages.BlockType
      def container?, do: false

      @doc false
      def __data_events__, do: unquote(data_events_str)

      @impl Phoenix.LiveComponent
      def render(var!(assigns)) do
        ~H"""
        <div
          id={@id}
          phx-hook="OraBlock"
          phx-update="ignore"
          phx-target={@myself}
          data-block-id={@block.id}
          data-events={__data_events__()}
        >
          {render_body(var!(assigns))}
        </div>
        """
      end

      unquote_splicing(event_clauses)

      defoverridable default_content: 0,
                     default_props: 0,
                     validate_props: 1,
                     container?: 0,
                     render: 1
    end
  end

  @doc false
  # The macro receives MFA values as either a raw 3-list `[mod, fun, args]`
  # (the supported form) or, transitionally, a quoted 3-tuple. Both shapes
  # are normalized here so the codegen loop sees the same structure.
  defp unwrap_mfa([_mod, _fun, _args] = list), do: list

  defp unwrap_mfa({:{}, _meta, [m, f, opts]}) when is_list(opts),
    do: [m, f, Keyword.fetch!(opts, :args)]

  defp unwrap_mfa(other) do
    raise CompileError,
      description:
        "ash_actions value must be [Module, :fun, [arg_atom, ...]]; got #{Macro.to_string(other)}"
  end

  defmacro __before_compile__(env) do
    unless Module.defines?(env.module, {:render_body, 1}) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description:
          "#{inspect(env.module)} uses Concept.Pages.BlockType.Interactive but does not define render_body/1"
    end

    quote do
      @doc false
      def __block_type_mcp_specs__ do
        Concept.Pages.BlockType.Interactive.build_mcp_specs(
          __MODULE__.type(),
          @__block_type_mcp_ash_actions__,
          @__block_type_mcp_descriptions__,
          @__block_type_mcp_only__,
          @__block_type_mcp_except__
        )
      end
    end
  end

  @doc false
  # Build MCP tool *specs* (verb, action_name, description) per ash_actions
  # entry. The Concept.Pages AutoTools transformer resolves these to full
  # %AshAi.Tool{} entries at domain-compile time.
  def build_mcp_specs(type, ash_actions, descriptions, only, except) do
    for {verb, [_mod, fun, _arg_atoms]} <- ash_actions,
        include_verb?(verb, only, except) do
      %{
        name: :"block_#{type}_#{verb}",
        action_name: fun,
        description: Keyword.get(descriptions, verb) || "#{verb} the #{type} block"
      }
    end
  end

  defp include_verb?(verb, nil, except), do: verb not in except
  defp include_verb?(verb, only, _except) when is_list(only), do: verb in only

  defp normalize_mcp_ash_actions(ash_actions) do
    for {verb, mfa} <- ash_actions do
      {verb, unwrap_mfa(mfa)}
    end
  end
end
