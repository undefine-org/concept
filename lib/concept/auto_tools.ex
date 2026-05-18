defmodule Concept.AutoTools do
  @moduledoc """
  Spark extension that auto-synthesizes MCP tool entries from every public
  Ash action that carries a non-nil `description`.

  This is the keystone of the *MCP parity by construction* principle (see
  `docs/mcp_parity.md`): the presence of a `description` on an action is
  sufficient to project it as an MCP tool — no manual `tool ...`
  declaration required.

  ## Usage

      use Ash.Domain,
        otp_app: :concept,
        extensions: [AshAdmin.Domain, AshAi, Concept.AutoTools]

  AshAi must also be in the extension list — this extension contributes new
  entities into AshAi's `tools` section.

  ## Synthesized tool naming

  `:"<resource_slug>_<action_name>"` where `resource_slug` is the resource
  module's last segment, `Macro.underscore`'d. Examples:

      Concept.Pages.Page :rename       → :page_rename
      Concept.Pages.Block :update_props → :block_update_props
      Concept.Knowledge.Citation :for_message → :citation_for_message

  ## Opt-out

  ### Global deny list (application config)

      config :concept, Concept.AutoTools,
        exclude: [
          {Concept.Pages.Page, :archive},
          {Concept.Knowledge.IngestionJob, :run}
        ]

  ### Manual `tool ...` always wins

  If a manual `tool :name, ...` entry already exists in the domain's
  `tools do ... end` block with the same `name` as what would be
  synthesized, the manual entry is kept and synthesis is skipped for
  that action.
  """
  use Spark.Dsl.Extension,
    transformers: [Concept.AutoTools.Transformers.SynthesizeTools]
end
