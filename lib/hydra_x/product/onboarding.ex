defmodule HydraX.Product.Onboarding do
  @moduledoc """
  Orchestrates the onboarding flow for new projects.
  Creates a "Getting started" board session with a seeded Strategist
  conversation so agents can start learning about the product immediately.
  """

  alias HydraX.Product
  alias HydraX.Product.AgentBridge

  @doc """
  Sets up a new project for onboarding:
  1. Creates a "Getting started" board session
  2. Creates a Strategist conversation linked to that session
  3. Seeds the conversation with the onboarding prompt

  Returns {:ok, %{session_id, conversation_id}} or {:error, reason}.
  """
  def setup_project!(project) do
    with {:ok, session} <-
           Product.create_board_session(project.id, %{
             "title" => "Getting started",
             "status" => "active",
             "metadata" => %{"onboarding" => true}
           }),
         {:ok, conversation} <-
           AgentBridge.ensure_project_conversation(project.id, "strategist", %{
             "board_session_id" => session.id,
             "channel" => "board_session",
             "external_ref" => "onboarding_#{project.id}",
             "title" => "Getting started with #{project.name}",
             "metadata" => %{"onboarding" => true}
           }) do
      # Seed the conversation with a hidden prompt that triggers the strategist greeting
      Task.start(fn ->
        AgentBridge.submit_message(
          conversation,
          seed_prompt(project.name),
          %{"onboarding" => true, "hidden" => true}
        )
      end)

      {:ok, %{session_id: session.id, conversation_id: conversation.id}}
    end
  end

  defp seed_prompt(project_name) do
    """
    The user just created a new project called "#{project_name}". This is their first interaction \
    with Hydra. Greet them warmly and guide them through onboarding.

    Your goal is to extract enough context for ALL agents to start working autonomously. \
    Ask about their product in a conversational way — cover these areas naturally:
    - What problem does it solve?
    - Who is it for?
    - What makes it different from existing solutions?
    - Competitors they know about
    - Their biggest uncertainty right now

    Don't dump all questions at once — be conversational, 1-2 questions at a time. \
    As you learn facts, use the project_context_update tool to store them. \
    Create draft strategy and decision nodes from what they tell you. \
    After 5+ messages with good coverage, summarize what you've learned \
    and confirm that autonomous work has started.
    """
  end
end
