defmodule Concept.Accounts.Reactors.Onboarding do
  @moduledoc """
  Post-signup orchestration:
    1. derive slug from email
    2. create personal Workspace
    3. create Membership (:owner)
  """
  use Ash.Reactor

  ash do
    default_domain Concept.Accounts
  end

  input :user

  step :slug do
    argument :user, input(:user)

    run fn %{user: user}, _ ->
      {:ok, Concept.Accounts.Slugs.from_email(to_string(user.email))}
    end
  end

  step :user_name do
    argument :user, input(:user)

    run fn %{user: user}, _ ->
      label = user.email |> to_string() |> String.split("@") |> hd()
      {:ok, "#{label}'s workspace"}
    end
  end

  step :system_actor do
    run fn _, _ -> {:ok, %{system?: true}} end
  end

  create :workspace, Concept.Accounts.Workspace, :create_personal do
    inputs %{
      name: result(:user_name),
      slug: result(:slug),
      icon_emoji: value("🏠"),
      owner_id: input(:user, [:id]),
      primary?: value(true)
    }

    actor result(:system_actor)
  end

  create :membership, Concept.Accounts.Membership, :create do
    inputs %{
      workspace_id: result(:workspace, [:id]),
      user_id: input(:user, [:id]),
      role: value(:owner)
    }

    actor result(:system_actor)
  end

  return :workspace
end
