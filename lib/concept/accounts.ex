defmodule Concept.Accounts do
  use Ash.Domain, otp_app: :concept, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Concept.Accounts.Token
    resource Concept.Accounts.User
  end
end
