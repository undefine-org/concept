defmodule Concept.Accounts do
  @moduledoc "Identity & tenancy: User, Token, Workspace, Membership."
  use Ash.Domain, otp_app: :concept, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Concept.Accounts.Token
    resource Concept.Accounts.User
    resource Concept.Accounts.Workspace
    resource Concept.Accounts.Membership
  end
end
