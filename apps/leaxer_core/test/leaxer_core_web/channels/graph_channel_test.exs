defmodule LeaxerCoreWeb.GraphChannelTest do
  use LeaxerCoreWeb.ChannelCase, async: false

  alias LeaxerCoreWeb.GraphChannel

  @moduletag :capture_log

  describe "list_models" do
    test "responds immediately with loading status" do
      {:ok, _, socket} =
        LeaxerCoreWeb.UserSocket
        |> socket("user_id", %{})
        |> subscribe_and_join(GraphChannel, "graph:main")

      # Push list_models and verify immediate response
      ref = push(socket, "list_models", %{})
      assert_reply ref, :ok, %{status: "loading"}
    end

    test "pushes models_list event asynchronously" do
      {:ok, _, socket} =
        LeaxerCoreWeb.UserSocket
        |> socket("user_id", %{})
        |> subscribe_and_join(GraphChannel, "graph:main")

      # Push list_models
      push(socket, "list_models", %{})

      # Should receive models_list push event (may be empty array if dir doesn't exist)
      assert_push "models_list", %{models: models}
      assert is_list(models)
    end

    test "does not block channel during file operations" do
      {:ok, _, socket} =
        LeaxerCoreWeb.UserSocket
        |> socket("user_id", %{})
        |> subscribe_and_join(GraphChannel, "graph:main")

      # Send list_models
      ref = push(socket, "list_models", %{})

      # Should respond immediately (within 100ms)
      # If it were blocking, it would potentially take much longer on slow storage
      assert_reply ref, :ok, %{status: "loading"}, 100

      # Ping should also respond immediately (verifying channel is not blocked)
      ping_ref = push(socket, "ping", %{})
      assert_reply ping_ref, :ok, %{pong: true}, 100
    end
  end

  describe "ping" do
    test "responds with pong" do
      {:ok, _, socket} =
        LeaxerCoreWeb.UserSocket
        |> socket("user_id", %{})
        |> subscribe_and_join(GraphChannel, "graph:main")

      ref = push(socket, "ping", %{})
      assert_reply ref, :ok, %{pong: true}
    end
  end

  describe "join" do
    test "successfully joins graph:main channel" do
      {:ok, _, socket} =
        LeaxerCoreWeb.UserSocket
        |> socket("user_id", %{})
        |> subscribe_and_join(GraphChannel, "graph:main")

      assert socket.joined
    end

    test "sends queue state after join" do
      {:ok, _, socket} =
        LeaxerCoreWeb.UserSocket
        |> socket("user_id", %{})
        |> subscribe_and_join(GraphChannel, "graph:main")

      # Should receive queue_updated push shortly after join
      # The payload structure includes jobs, current_job_id, is_processing, etc.
      assert_push "queue_updated", %{jobs: _, is_processing: _}
    end
  end
end
