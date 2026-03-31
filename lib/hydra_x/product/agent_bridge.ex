defmodule HydraX.Product.AgentBridge do
  @moduledoc """
  Bridges product conversations onto the existing Hydra runtime.
  """

  import Ecto.Query

  alias HydraX.Agent
  alias HydraX.Product
  alias HydraX.Product.ProductConversation
  alias HydraX.Product.ProductMessage
  alias HydraX.Product.PubSub, as: ProductPubSub
  alias HydraX.Repo
  alias HydraX.Runtime

  def list_project_conversations(project_or_id, opts \\ []) do
    Product.list_product_conversations(project_or_id, opts)
  end

  def get_project_conversation!(project_or_id, conversation_id) do
    product_conversation = Product.get_product_conversation!(project_or_id, conversation_id)
    hydra_conversation = Runtime.get_conversation!(product_conversation.hydra_conversation_id)
    sync_messages!(product_conversation, hydra_conversation)
    Product.get_product_conversation!(project_or_id, conversation_id)
  end

  def ensure_project_conversation(project_or_id, persona, attrs \\ %{}) do
    project = load_project(project_or_id)
    persona = normalize_persona(persona)
    agent = agent_for_persona!(project, persona)
    params = normalize_attrs(attrs)

    hydra_conversation =
      case params["external_ref"] do
        value when is_binary(value) and value != "" ->
          Runtime.find_conversation(agent.id, params["channel"], value) ||
            start_hydra_conversation!(project, agent, persona, params)

        _ ->
          start_hydra_conversation!(project, agent, persona, params)
      end

    {product_conversation, created?} =
      Repo.get_by(ProductConversation, hydra_conversation_id: hydra_conversation.id)
      |> case do
        nil ->
          conversation_attrs = %{
              "project_id" => project.id,
              "hydra_conversation_id" => hydra_conversation.id,
              "persona" => persona,
              "title" => params["title"] || hydra_conversation.title,
              "status" => "active",
              "metadata" => params["metadata"] || %{}
            }

          conversation_attrs =
            if params["board_session_id"],
              do: Map.put(conversation_attrs, "board_session_id", params["board_session_id"]),
              else: conversation_attrs

          conversation =
            %ProductConversation{}
            |> ProductConversation.changeset(conversation_attrs)
            |> Repo.insert!()

          {conversation, true}

        %ProductConversation{} = conversation ->
          {conversation, false}
      end

    product_conversation = Repo.preload(product_conversation, [:project, :hydra_conversation])

    sync_messages!(product_conversation, Runtime.get_conversation!(hydra_conversation.id))

    refreshed = Product.get_product_conversation!(project.id, product_conversation.id)

    if created? do
      ProductPubSub.broadcast_project_event(project.id, "conversation.created", refreshed)
    end

    {:ok, refreshed}
  end

  def submit_message(product_conversation_or_id, content, metadata \\ %{}) do
    product_conversation =
      product_conversation_or_id
      |> load_product_conversation()
      |> Repo.preload([:project, :hydra_conversation])

    hydra_conversation = Runtime.get_conversation!(product_conversation.hydra_conversation_id)
    project = Product.get_project!(product_conversation.project_id)
    agent = agent_for_persona!(project, product_conversation.persona)

    {:ok, _pid} = Agent.ensure_started(agent)
    existing_turn_ids = existing_turn_ids(product_conversation.id)

    result =
      HydraX.Agent.Channel.submit(
        agent,
        hydra_conversation,
        content,
        Map.merge(%{"product_conversation_id" => product_conversation.id}, metadata || %{})
      )

    refreshed = Runtime.get_conversation!(hydra_conversation.id)
    inserted_messages = sync_messages!(product_conversation, refreshed, existing_turn_ids)
    refreshed_product_conversation = Product.get_product_conversation!(product_conversation.id)

    Enum.each(inserted_messages, fn message ->
      ProductPubSub.broadcast_project_event(project.id, "message.created", %{
        conversation: refreshed_product_conversation,
        message: message
      })
    end)

    ProductPubSub.broadcast_project_event(
      project.id,
      "conversation.updated",
      refreshed_product_conversation
    )

    {:ok,
     %{
       product_conversation: refreshed_product_conversation,
       hydra_conversation: refreshed,
       response: result
     }}
  end

  def update_project_conversation(project_or_id, product_conversation_or_id, attrs) do
    project = load_project(project_or_id)
    product_conversation = load_product_conversation(product_conversation_or_id)
    product_conversation = Repo.preload(product_conversation, [:project, :hydra_conversation])

    hydra_attrs =
      attrs
      |> HydraX.Runtime.Helpers.normalize_string_keys()
      |> Map.take(["title", "status"])

    Repo.transaction(fn ->
      if hydra_attrs != %{} do
        product_conversation.hydra_conversation
        |> Runtime.save_conversation(hydra_attrs)
        |> case do
          {:ok, hydra_conversation} -> hydra_conversation
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end

      Product.update_product_conversation(product_conversation, attrs)
      |> case do
        {:ok, updated} -> updated
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, updated} ->
        refreshed = Product.get_product_conversation!(project.id, updated.id)

        Phoenix.PubSub.broadcast(
          HydraX.PubSub,
          "conversations",
          {:conversation_updated, refreshed.hydra_conversation_id}
        )

        ProductPubSub.broadcast_project_event(project.id, "conversation.updated", refreshed)
        {:ok, refreshed}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def export_project_conversation!(project_or_id, conversation_id) do
    conversation = get_project_conversation!(project_or_id, conversation_id)
    Runtime.export_conversation_transcript!(conversation.hydra_conversation_id)
  end

  defp start_hydra_conversation!(project, agent, persona, params) do
    board_session_id = params["board_session_id"]

    metadata =
      %{
        "product_project_id" => project.id,
        "product_project_slug" => project.slug,
        "product_persona" => persona
      }
      |> then(fn m ->
        if board_session_id, do: Map.put(m, "board_session_id", board_session_id), else: m
      end)
      |> Map.merge(params["metadata"] || %{})

    {:ok, hydra_conversation} =
      Runtime.start_conversation(agent, %{
        channel: params["channel"],
        external_ref: params["external_ref"],
        title: params["title"] || default_title(project, persona),
        metadata: metadata
      })

    hydra_conversation
  end

  defp sync_messages!(product_conversation, hydra_conversation, existing_turn_ids \\ nil) do
    existing_turn_ids = existing_turn_ids || existing_turn_ids(product_conversation.id)

    hydra_conversation.turns
    |> Enum.reject(&MapSet.member?(existing_turn_ids, &1.id))
    |> Enum.map(fn turn ->
      {content, citations} =
        Product.parse_citations(product_conversation.project_id, turn.content)

      %ProductMessage{}
      |> ProductMessage.changeset(%{
        "product_conversation_id" => product_conversation.id,
        "hydra_turn_id" => turn.id,
        "role" => turn.role,
        "content" => content,
        "citations" => citations,
        "metadata" => turn.metadata || %{}
      })
      |> Repo.insert!()
    end)
  end

  defp existing_turn_ids(product_conversation_id) do
    ProductMessage
    |> where([message], message.product_conversation_id == ^product_conversation_id)
    |> where([message], not is_nil(message.hydra_turn_id))
    |> select([message], message.hydra_turn_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp load_project(%Product.Project{} = project),
    do: Repo.preload(project, [:researcher_agent, :strategist_agent])

  defp load_project(id) when is_integer(id), do: Product.get_project!(id)

  defp load_project(id) when is_binary(id),
    do: id |> String.to_integer() |> Product.get_project!()

  defp load_product_conversation(%ProductConversation{} = conversation), do: conversation
  defp load_product_conversation(id) when is_integer(id), do: Repo.get!(ProductConversation, id)

  defp load_product_conversation(id) when is_binary(id) do
    Repo.get!(ProductConversation, String.to_integer(id))
  end

  defp agent_for_persona!(project, "researcher"),
    do: project.researcher_agent || Runtime.get_agent!(project.researcher_agent_id)

  defp agent_for_persona!(project, "strategist"),
    do: project.strategist_agent || Runtime.get_agent!(project.strategist_agent_id)

  defp agent_for_persona!(project, "architect"),
    do: project.architect_agent || Runtime.get_agent!(project.architect_agent_id)

  defp agent_for_persona!(project, "designer"),
    do: project.designer_agent || Runtime.get_agent!(project.designer_agent_id)

  defp agent_for_persona!(project, "memory_agent"),
    do: project.memory_agent || Runtime.get_agent!(project.memory_agent_id)

  defp normalize_attrs(attrs) do
    attrs = HydraX.Runtime.Helpers.normalize_string_keys(attrs)

    attrs
    |> Map.put_new("channel", "product_chat")
    |> Map.put_new("metadata", %{})
  end

  defp normalize_persona(persona) when persona in ["researcher", :researcher], do: "researcher"
  defp normalize_persona(persona) when persona in ["strategist", :strategist], do: "strategist"
  defp normalize_persona(persona) when persona in ["architect", :architect], do: "architect"
  defp normalize_persona(persona) when persona in ["designer", :designer], do: "designer"
  defp normalize_persona(persona) when persona in ["memory_agent", :memory_agent], do: "memory_agent"

  defp default_title(project, persona) do
    "#{project.name} #{String.capitalize(persona)} conversation"
  end
end
