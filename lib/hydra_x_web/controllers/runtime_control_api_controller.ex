defmodule HydraXWeb.RuntimeControlAPIController do
  @moduledoc """
  Runtime-level control endpoints for a product conversation:

    * Branches: list, fork, switch active branch
    * Steering: queue a mid-processing steering message
    * Models: list available, switch per-conversation override

  These all operate on the underlying `hx_conversations` row via the
  product conversation's `hydra_conversation_id`.
  """

  use HydraXWeb, :controller

  alias HydraX.Agent.Channel
  alias HydraX.Product.AgentBridge
  alias HydraX.Product.ProductConversation
  alias HydraX.Repo
  alias HydraX.Runtime.{Conversation, Providers, SessionBranches, Turn}
  alias HydraX.Tools.SwitchModel

  action_fallback HydraXWeb.ProjectAPIFallbackController

  # --- Branches ---

  def list_branches(conn, %{"project_id" => project_id, "id" => id}) do
    with {:ok, runtime_id} <- runtime_conversation_id(project_id, id) do
      tree = SessionBranches.tree(runtime_id)
      active = SessionBranches.active_branch(runtime_id)

      active_uuid =
        case active do
          nil -> nil
          branch -> branch.branch_uuid
        end

      json(conn, %{
        data: %{
          branches: Enum.map(tree, &branch_json(&1, active_uuid)),
          active_branch_uuid: active_uuid
        }
      })
    end
  end

  def create_branch(conn, %{"project_id" => project_id, "id" => id} = params) do
    with {:ok, runtime_id} <- runtime_conversation_id(project_id, id),
         {:ok, turn_id} <- parse_int(params["from_turn_id"]),
         {:ok, from_turn} <- fetch_turn(runtime_id, turn_id),
         label when is_binary(label) and label != "" <- params["label"] || "branch" do
      case SessionBranches.fork(from_turn, label) do
        {:ok, branch} ->
          conn
          |> put_status(:created)
          |> json(%{data: branch_json(tree_entry_for(runtime_id, branch), branch.branch_uuid)})

        {:error, %Ecto.Changeset{} = cs} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: changeset_errors(cs)})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: inspect(reason)})
      end
    else
      {:error, :turn_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "turn not found"})

      {:error, :invalid_int} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "from_turn_id required and must be an integer"})

      nil ->
        conn |> put_status(:bad_request) |> json(%{error: "label required"})

      "" ->
        conn |> put_status(:bad_request) |> json(%{error: "label required"})

      other ->
        other
    end
  end

  defp parse_int(n) when is_integer(n) and n > 0, do: {:ok, n}

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :invalid_int}
    end
  end

  defp parse_int(_), do: {:error, :invalid_int}

  def activate_branch(conn, %{"project_id" => project_id, "id" => id, "branch_uuid" => uuid}) do
    with {:ok, runtime_id} <- runtime_conversation_id(project_id, id) do
      case SessionBranches.switch(runtime_id, uuid) do
        {:ok, _conv} ->
          json(conn, %{data: %{active_branch_uuid: uuid}})

        {:error, :branch_not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "branch not found"})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: inspect(reason)})
      end
    end
  end

  # --- Steering ---

  def steer(conn, %{"project_id" => project_id, "id" => id, "content" => content})
      when is_binary(content) and content != "" do
    with {:ok, runtime_id} <- runtime_conversation_id(project_id, id) do
      case Channel.steer(runtime_id, content) do
        :ok ->
          json(conn, %{data: %{queued: true}})

        {:error, :not_processing} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "conversation is not processing; use a normal message instead"})

        {:error, :not_running} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: "no active channel for this conversation"})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: inspect(reason)})
      end
    end
  end

  def steer(conn, _params),
    do: conn |> put_status(:bad_request) |> json(%{error: "content required"})

  # --- Models ---

  def list_models(conn, %{"project_id" => project_id, "id" => id}) do
    with {:ok, runtime_id} <- runtime_conversation_id(project_id, id) do
      models = Providers.list_available_models()
      current = current_model_override(runtime_id)

      json(conn, %{
        data: %{
          available: models,
          current_override: current
        }
      })
    end
  end

  def switch_model(conn, %{"project_id" => project_id, "id" => id} = params) do
    with {:ok, runtime_id} <- runtime_conversation_id(project_id, id) do
      result =
        SwitchModel.execute(
          %{
            "conversation_id" => runtime_id,
            "model" => params["model"],
            "reason" => params["reason"]
          },
          %{}
        )

      case result do
        {:ok, payload} ->
          json(conn, %{data: payload})

        {:error, {:model_not_available, model, models}} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            error: "model_not_available",
            model: model,
            available: models
          })

        {:error, {:model_not_allowed, model, allowed}} ->
          conn
          |> put_status(:forbidden)
          |> json(%{error: "model_not_allowed", model: model, allowed: allowed})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: inspect(reason)})
      end
    end
  end

  # --- Helpers ---

  defp runtime_conversation_id(project_id, product_conv_id) do
    try do
      conversation =
        AgentBridge.get_project_conversation!(project_id, product_conv_id)

      case conversation do
        %ProductConversation{hydra_conversation_id: id} when is_integer(id) ->
          {:ok, id}

        _ ->
          {:error, :no_runtime_conversation}
      end
    rescue
      Ecto.NoResultsError -> {:error, :not_found}
    end
  end

  defp fetch_turn(runtime_id, turn_id) do
    case Repo.get_by(Turn, id: turn_id, conversation_id: runtime_id) do
      nil -> {:error, :turn_not_found}
      %Turn{} = turn -> {:ok, turn}
    end
  end

  defp branch_json(entry, active_uuid) do
    %{
      id: entry.id,
      branch_uuid: entry.branch_uuid,
      label: entry.label,
      parent_branch_id: entry.parent_branch_id,
      forked_from_sequence: entry.forked_from_sequence,
      turn_count: entry.turn_count,
      inserted_at: entry.inserted_at,
      active: entry.branch_uuid == active_uuid
    }
  end

  defp tree_entry_for(runtime_id, branch) do
    runtime_id
    |> SessionBranches.tree()
    |> Enum.find(fn entry -> entry.branch_uuid == branch.branch_uuid end) ||
      %{
        id: branch.id,
        branch_uuid: branch.branch_uuid,
        label: branch.label,
        parent_branch_id: branch.parent_branch_id,
        forked_from_sequence: branch.forked_from_sequence,
        turn_count: 0,
        inserted_at: branch.inserted_at
      }
  end

  defp current_model_override(runtime_id) do
    case Repo.get(Conversation, runtime_id) do
      %Conversation{metadata: %{"model_override_model" => model}} -> model
      _ -> nil
    end
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
  end
end
