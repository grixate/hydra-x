defmodule HydraX.Runtime do
  @moduledoc """
  Persistence and orchestration helpers for agents, conversations, providers, and checkpoints.
  """

  import Ecto.Query

  alias HydraX.Config
  alias HydraX.Repo
  alias HydraX.Runtime.{AgentProfile, Checkpoint, Conversation, ProviderConfig, Turn}

  @default_agent_slug "hydra-primary"

  def list_agents do
    AgentProfile
    |> order_by([agent], desc: agent.is_default, asc: agent.name)
    |> Repo.all()
  end

  def get_agent!(id), do: Repo.get!(AgentProfile, id)

  def get_agent_by_slug(slug) do
    Repo.get_by(AgentProfile, slug: slug)
  end

  def get_default_agent do
    Repo.one(from agent in AgentProfile, where: agent.is_default == true, limit: 1)
  end

  def ensure_default_agent! do
    case get_default_agent() || get_agent_by_slug(@default_agent_slug) do
      nil ->
        attrs = %{
          name: "Hydra Prime",
          slug: @default_agent_slug,
          status: "active",
          description: "Default Hydra-X operator agent",
          is_default: true,
          workspace_root: Config.default_workspace(@default_agent_slug)
        }

        case save_agent(attrs) do
          {:ok, agent} ->
            HydraX.Workspace.Scaffold.copy_template!(agent.workspace_root)
            agent

          {:error, _changeset} ->
            get_agent_by_slug(@default_agent_slug)
        end

      agent ->
        HydraX.Workspace.Scaffold.copy_template!(agent.workspace_root)
        agent
    end
  end

  def change_agent(agent \\ %AgentProfile{}, attrs \\ %{}) do
    AgentProfile.changeset(agent, attrs)
  end

  def save_agent(attrs) when is_map(attrs) do
    save_agent(%AgentProfile{}, attrs)
  end

  def save_agent(%AgentProfile{} = agent, attrs) do
    Repo.transaction(fn ->
      attrs = normalize_agent_attrs(attrs)
      changeset = AgentProfile.changeset(agent, attrs)

      record =
        case Repo.insert_or_update(changeset) do
          {:ok, record} -> record
          {:error, changeset} -> Repo.rollback(changeset)
        end

      if record.is_default do
        from(other in AgentProfile, where: other.id != ^record.id and other.is_default == true)
        |> Repo.update_all(set: [is_default: false])
      end

      HydraX.Workspace.Scaffold.copy_template!(record.workspace_root)
      record
    end)
    |> unwrap_transaction()
  end

  def update_agent_runtime_state(%AgentProfile{} = agent, attrs) when is_map(attrs) do
    current = agent.runtime_state || %{}
    save_agent(agent, %{runtime_state: Map.merge(current, attrs)})
  end

  def toggle_agent_status!(id) do
    agent = get_agent!(id)
    next = if agent.status == "active", do: "paused", else: "active"
    {:ok, updated} = save_agent(agent, %{status: next})
    updated
  end

  def list_provider_configs do
    ProviderConfig
    |> order_by([provider], desc: provider.enabled, asc: provider.name)
    |> Repo.all()
  end

  def enabled_provider do
    Repo.one(from provider in ProviderConfig, where: provider.enabled == true, limit: 1)
  end

  def change_provider_config(provider \\ %ProviderConfig{}, attrs \\ %{}) do
    ProviderConfig.changeset(provider, attrs)
  end

  def save_provider_config(attrs) when is_map(attrs) do
    save_provider_config(%ProviderConfig{}, attrs)
  end

  def save_provider_config(%ProviderConfig{} = provider, attrs) do
    Repo.transaction(fn ->
      changeset = ProviderConfig.changeset(provider, attrs)

      record =
        case Repo.insert_or_update(changeset) do
          {:ok, record} -> record
          {:error, changeset} -> Repo.rollback(changeset)
        end

      if record.enabled do
        from(other in ProviderConfig, where: other.id != ^record.id and other.enabled == true)
        |> Repo.update_all(set: [enabled: false])
      end

      record
    end)
    |> unwrap_transaction()
  end

  def list_conversations(opts \\ []) do
    agent_id = Keyword.get(opts, :agent_id)
    limit = Keyword.get(opts, :limit, 25)

    Conversation
    |> preload([:agent])
    |> maybe_filter_agent(agent_id)
    |> order_by([conversation], desc: conversation.updated_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_conversation!(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload([:agent, turns: from(turn in Turn, order_by: turn.sequence)])
  end

  def find_conversation(agent_id, channel, external_ref) do
    Repo.get_by(Conversation, agent_id: agent_id, channel: channel, external_ref: external_ref)
  end

  def start_conversation(%AgentProfile{} = agent, attrs \\ %{}) do
    attrs = normalize_string_keys(attrs)

    params = %{
      agent_id: agent.id,
      channel: Map.get(attrs, "channel", "cli"),
      status: Map.get(attrs, "status", "active"),
      title: Map.get(attrs, "title", agent.name),
      external_ref: Map.get(attrs, "external_ref"),
      metadata: Map.get(attrs, "metadata", %{}),
      last_message_at: DateTime.utc_now()
    }

    %Conversation{}
    |> Conversation.changeset(params)
    |> Repo.insert()
  end

  def list_turns(conversation_id) do
    Turn
    |> where([turn], turn.conversation_id == ^conversation_id)
    |> order_by([turn], asc: turn.sequence)
    |> Repo.all()
  end

  def append_turn(%Conversation{} = conversation, attrs) do
    sequence =
      Repo.one(
        from turn in Turn,
          where: turn.conversation_id == ^conversation.id,
          select: coalesce(max(turn.sequence), 0)
      ) + 1

    params =
      attrs
      |> normalize_string_keys()
      |> Map.merge(%{
        "conversation_id" => conversation.id,
        "sequence" => sequence,
        "metadata" => Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
      })

    Repo.transaction(fn ->
      turn =
        %Turn{}
        |> Turn.changeset(params)
        |> Repo.insert!()

      conversation
      |> Conversation.changeset(%{last_message_at: DateTime.utc_now()})
      |> Repo.update!()

      turn
    end)
    |> unwrap_transaction()
  end

  def get_checkpoint(conversation_id, process_type) do
    Repo.get_by(Checkpoint, conversation_id: conversation_id, process_type: process_type)
  end

  def upsert_checkpoint(conversation_id, process_type, state) when is_map(state) do
    checkpoint = get_checkpoint(conversation_id, process_type) || %Checkpoint{}

    checkpoint
    |> Checkpoint.changeset(%{
      conversation_id: conversation_id,
      process_type: process_type,
      state: state
    })
    |> Repo.insert_or_update()
  end

  def health_snapshot do
    provider = enabled_provider()

    [
      %{name: "database", status: :ok, detail: "SQLite repo online"},
      %{
        name: "agents",
        status: if(list_agents() == [], do: :warn, else: :ok),
        detail: "#{length(list_agents())} configured"
      },
      %{
        name: "providers",
        status: if(provider, do: :ok, else: :warn),
        detail: (provider && "#{provider.kind}: #{provider.model}") || "mock fallback"
      },
      %{
        name: "workspace",
        status: :ok,
        detail: Config.workspace_root()
      }
    ]
  end

  defp maybe_filter_agent(query, nil), do: query

  defp maybe_filter_agent(query, agent_id),
    do: where(query, [conversation], conversation.agent_id == ^agent_id)

  defp normalize_agent_attrs(attrs) do
    attrs
    |> normalize_string_keys()
    |> Map.put_new(
      "workspace_root",
      Config.default_workspace(Map.get(attrs, :slug, attrs["slug"] || @default_agent_slug))
    )
  end

  defp normalize_string_keys(attrs) do
    Enum.reduce(attrs, %{}, fn
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp unwrap_transaction({:ok, value}), do: {:ok, value}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}
end
