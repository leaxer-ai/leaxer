defmodule LeaxerCore.LogBroadcaster do
  @moduledoc """
  Broadcasts logs to WebSocket clients via PubSub using Erlang's :logger handler.
  Maintains a ring buffer of recent logs for new subscribers.

  ## Supervision

  - **Restart**: Permanent (always restarted)
  - **Strategy**: Part of main supervision tree with `:one_for_one`

  ## Failure Modes

  - **Crash during log handling**: Logger handler is removed, logs stop broadcasting.
    On restart, handler is re-attached after 100ms delay.
  - **PubSub unavailable**: Broadcasts fail silently, logs still buffered locally.

  ## State Recovery

  On restart, the log buffer is lost. New clients will only see logs generated
  after the restart. The :logger handler re-attaches automatically via `init/1`.
  """
  use GenServer

  @max_buffer_size 1000
  @batch_interval_ms 100
  @pubsub LeaxerCore.PubSub
  @topic "logs:stream"
  @handler_id :lumex_log_broadcaster

  # =============================================================================
  # Public API
  # =============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get recent logs from the buffer.
  """
  def get_recent_logs(count \\ 100) do
    GenServer.call(__MODULE__, {:get_recent_logs, count})
  catch
    :exit, _ -> []
  end

  # =============================================================================
  # GenServer Callbacks
  # =============================================================================

  @impl true
  def init(_opts) do
    state = %{
      buffer: :queue.new(),
      buffer_size: 0,
      pending_batch: [],
      timer_ref: nil
    }

    # Attach the logger handler after a short delay to ensure PubSub is ready
    Process.send_after(self(), :attach_handler, 100)

    {:ok, state}
  end

  @impl true
  def handle_call({:get_recent_logs, count}, _from, state) do
    logs =
      state.buffer
      |> :queue.to_list()
      |> Enum.take(-count)

    {:reply, logs, state}
  end

  @impl true
  def handle_info(:attach_handler, state) do
    # Remove existing handler if present
    :logger.remove_handler(@handler_id)

    # Add our custom handler
    handler_config = %{
      config: %{broadcaster_pid: self()},
      level: :debug,
      formatter: {:logger_formatter, %{}}
    }

    case :logger.add_handler(@handler_id, __MODULE__, handler_config) do
      :ok ->
        :ok

      {:error, reason} ->
        IO.puts("[LogBroadcaster] Failed to add handler: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  def handle_info({:log_event, log_entry}, state) do
    state = add_to_buffer(state, log_entry)
    state = add_to_pending_batch(state, log_entry)
    state = maybe_schedule_broadcast(state)
    {:noreply, state}
  end

  def handle_info(:broadcast_batch, state) do
    state = broadcast_pending_batch(state)
    {:noreply, %{state | timer_ref: nil}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :logger.remove_handler(@handler_id)
    :ok
  end

  # =============================================================================
  # Erlang :logger Handler Callbacks
  # =============================================================================

  @doc false
  def log(%{level: level, msg: msg, meta: meta}, %{config: %{broadcaster_pid: pid}}) do
    # Format the message
    message =
      case msg do
        {:string, str} ->
          IO.chardata_to_string(str)

        {:report, report} ->
          inspect(report)

        {format, args} when is_list(args) ->
          :io_lib.format(format, args) |> IO.chardata_to_string()

        other ->
          inspect(other)
      end

    # Get timestamp
    timestamp =
      case Map.get(meta, :time) do
        nil ->
          DateTime.utc_now() |> DateTime.to_iso8601()

        microseconds when is_integer(microseconds) ->
          microseconds
          |> DateTime.from_unix!(:microsecond)
          |> DateTime.to_iso8601()
      end

    log_entry = %{
      id: generate_id(),
      timestamp: timestamp,
      level: Atom.to_string(level),
      message: message,
      metadata: format_metadata(meta)
    }

    # Send to GenServer for buffering and broadcasting
    send(pid, {:log_event, log_entry})
  end

  # Handler config callback (required by :logger)
  @doc false
  def adding_handler(config) do
    {:ok, config}
  end

  @doc false
  def removing_handler(_config) do
    :ok
  end

  @doc false
  def changing_config(_action, _old_config, new_config) do
    {:ok, new_config}
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp format_metadata(meta) do
    meta
    |> Map.drop([:time, :gl, :pid, :mfa, :file, :line, :domain, :error_logger])
    |> Enum.into(%{}, fn {k, v} -> {to_string(k), inspect(v)} end)
  end

  defp add_to_buffer(state, log_entry) do
    buffer = :queue.in(log_entry, state.buffer)
    buffer_size = state.buffer_size + 1

    if buffer_size > @max_buffer_size do
      {{:value, _}, buffer} = :queue.out(buffer)
      %{state | buffer: buffer, buffer_size: @max_buffer_size}
    else
      %{state | buffer: buffer, buffer_size: buffer_size}
    end
  end

  defp add_to_pending_batch(state, log_entry) do
    %{state | pending_batch: [log_entry | state.pending_batch]}
  end

  defp maybe_schedule_broadcast(state) do
    if state.timer_ref == nil do
      timer_ref = Process.send_after(self(), :broadcast_batch, @batch_interval_ms)
      %{state | timer_ref: timer_ref}
    else
      state
    end
  end

  defp broadcast_pending_batch(%{pending_batch: []} = state), do: state

  defp broadcast_pending_batch(state) do
    logs = Enum.reverse(state.pending_batch)
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:log_batch, logs})
    %{state | pending_batch: []}
  end
end
