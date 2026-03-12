defmodule HydraXWeb.WebchatLiveTest do
  use HydraXWeb.ConnCase

  alias HydraX.Runtime

  test "public webchat opens a conversation and renders replies", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()
    {:ok, _pid} = HydraX.Agent.ensure_started(agent)

    {:ok, _webchat} =
      Runtime.save_webchat_config(%{
        title: "Hydra-X Browser",
        subtitle: "Public runtime ingress",
        welcome_prompt: "Welcome to Hydra-X Webchat.",
        composer_placeholder: "Ask Hydra-X",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, view, html} = live(conn, ~p"/webchat")

    assert html =~ "Hydra-X Browser"
    assert html =~ "Welcome to Hydra-X Webchat."
    assert html =~ "awaiting first message"
    assert html =~ "Turn count"

    view
    |> form("form[phx-submit=\"send_message\"]", %{
      "message" => %{"message" => "Webchat should persist and respond."}
    })
    |> render_submit()

    rendered = render(view)
    assert rendered =~ "Webchat should persist and respond."
    assert rendered =~ "Mock response"
    assert rendered =~ "conversation active"
    assert rendered =~ "Turn count"
  end

  test "webchat requires a saved display name when anonymous access is disabled", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()
    {:ok, _pid} = HydraX.Agent.ensure_started(agent)

    {:ok, _webchat} =
      Runtime.save_webchat_config(%{
        title: "Hydra-X Browser",
        enabled: true,
        allow_anonymous_messages: false,
        attachments_enabled: true,
        max_attachment_count: 2,
        max_attachment_size_kb: 512,
        default_agent_id: agent.id
      })

    {:ok, view, html} = live(conn, ~p"/webchat")

    assert html =~ "display name required"

    view
    |> form("form[phx-submit=\"send_message\"]", %{
      "message" => %{"message" => "Anonymous should be blocked."}
    })
    |> render_submit()

    assert render(view) =~ "display name required"
    assert Runtime.list_conversations(agent_id: agent.id, limit: 10) == []

    conn =
      conn
      |> post(~p"/webchat/session", %{
        "webchat_identity" => %{"display_name" => "Browser Visitor"}
      })
      |> recycle()

    {:ok, named_view, named_html} = live(conn, ~p"/webchat")

    assert named_html =~ "identity locked to Browser Visitor"

    named_view
    |> form("form[phx-submit=\"send_message\"]", %{
      "message" => %{"message" => "Named session should persist and respond."}
    })
    |> render_submit()

    assert render(named_view) =~ "Browser Visitor"
    assert render(named_view) =~ "Named session should persist and respond."
  end

  test "webchat uploads attachment metadata into the conversation", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()
    {:ok, _pid} = HydraX.Agent.ensure_started(agent)

    {:ok, _webchat} =
      Runtime.save_webchat_config(%{
        title: "Hydra-X Browser",
        enabled: true,
        allow_anonymous_messages: true,
        attachments_enabled: true,
        max_attachment_count: 2,
        max_attachment_size_kb: 512,
        default_agent_id: agent.id
      })

    conn =
      conn
      |> post(~p"/webchat/session", %{
        "webchat_identity" => %{"display_name" => "Attachment Visitor"}
      })
      |> recycle()

    {:ok, view, _html} = live(conn, ~p"/webchat")

    upload =
      file_input(view, "form[phx-submit=\"send_message\"]", :attachments, [
        %{
          name: "notes.txt",
          content: "attachment body",
          type: "text/plain"
        }
      ])

    render_upload(upload, "notes.txt")

    view
    |> form("form[phx-submit=\"send_message\"]", %{
      "message" => %{"message" => ""}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "[Webchat attachments: text/plain]"
    assert html =~ "Attachment Visitor"
    assert html =~ "notes.txt"
  end

  test "webchat rebuilds streaming content from checkpoint snapshots", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()
    {:ok, _pid} = HydraX.Agent.ensure_started(agent)
    now = System.system_time(:second)

    conn =
      init_test_session(conn,
        webchat_session_id: "streaming-session",
        webchat_session_created_at: now,
        webchat_session_last_active_at: now
      )

    {:ok, _webchat} =
      Runtime.save_webchat_config(%{
        title: "Hydra-X Browser",
        enabled: true,
        allow_anonymous_messages: true,
        default_agent_id: agent.id
      })

    session_ref = webchat_session_ref("streaming-session")

    {:ok, conversation} =
      Runtime.start_conversation(agent, %{
        channel: "webchat",
        title: "Streaming Webchat",
        external_ref: session_ref
      })

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "streaming",
        "stream_capture" => %{
          "content" => "Partial streamed webchat reply",
          "chunk_count" => 1,
          "provider" => "Mock Provider"
        },
        "execution_events" => []
      })

    {:ok, view, html} = live(conn, ~p"/webchat")

    assert html =~ "assistant streaming"
    assert html =~ "Partial streamed webchat reply"

    {:ok, _checkpoint} =
      Runtime.upsert_checkpoint(conversation.id, "channel", %{
        "status" => "streaming",
        "stream_capture" => %{
          "content" => "Partial streamed webchat reply with more detail",
          "chunk_count" => 2,
          "provider" => "Mock Provider"
        },
        "execution_events" => []
      })

    send(view.pid, {:conversation_updated, conversation.id})

    assert render(view) =~ "Partial streamed webchat reply with more detail"
  end

  test "webchat responds to adapter-native session stream previews", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()
    {:ok, _pid} = HydraX.Agent.ensure_started(agent)
    now = System.system_time(:second)

    conn =
      init_test_session(conn,
        webchat_session_id: "adapter-stream-session",
        webchat_session_created_at: now,
        webchat_session_last_active_at: now
      )

    {:ok, _webchat} =
      Runtime.save_webchat_config(%{
        title: "Hydra-X Browser",
        enabled: true,
        allow_anonymous_messages: true,
        default_agent_id: agent.id
      })

    session_ref = webchat_session_ref("adapter-stream-session")

    {:ok, _conversation} =
      Runtime.start_conversation(agent, %{
        channel: "webchat",
        title: "Adapter Streaming Webchat",
        external_ref: session_ref
      })

    {:ok, view, html} = live(conn, ~p"/webchat")
    refute html =~ "Adapter-native preview"

    Phoenix.PubSub.broadcast(
      HydraX.PubSub,
      HydraX.Gateway.Adapters.Webchat.session_topic(session_ref),
      {:webchat_stream_preview, session_ref, "Adapter-native preview", 2}
    )

    assert render(view) =~ "assistant streaming"
    assert render(view) =~ "Adapter-native preview"

    Phoenix.PubSub.broadcast(
      HydraX.PubSub,
      HydraX.Gateway.Adapters.Webchat.session_topic(session_ref),
      {:webchat_delivery, session_ref}
    )

    refute render(view) =~ "Adapter-native preview"
  end

  defp webchat_session_ref(session_id) do
    "webchat:" <>
      (:crypto.hash(:sha256, session_id)
       |> Base.encode16(case: :lower)
       |> String.slice(0, 20))
  end
end
