defmodule LeaxerCore.Models.DownloadManager do
  @moduledoc """
  GenServer for managing model file downloads with progress tracking.

  Features:
  - Real-time progress updates via PubSub
  - Resumable downloads using HTTP Range headers
  - Concurrent downloads with cancellation
  - Automatic retry on transient failures

  ## Supervision

  - **Restart**: Permanent (always restarted)
  - **Strategy**: Part of main supervision tree with `:one_for_one`
  - **Dependencies**: Requires `Finch` (HTTP client) and `Task.Supervisor` to be running

  ## Failure Modes

  - **GenServer crash**: All active downloads fail, clients get no response.
    On restart, download state is lost (not persisted).
  - **Task crash**: Individual download fails, GenServer handles `:DOWN` message
    and marks download as failed with retry logic.
  - **Network timeout**: Auto-retry up to 3 times with 2s delay between attempts.

  ## State Recovery

  Download state is held in memory only. On restart:
  - Active downloads are lost (partial files remain on disk)
  - Clients must re-initiate downloads
  - Partial files can be resumed via HTTP Range headers on next attempt
  """

  use GenServer
  require Logger

  alias LeaxerCore.Models.Registry
  alias LeaxerCore.Paths
  alias LeaxerCore.Security.PathValidator

  @progress_interval 250
  @http_timeout 1_800_000
  @max_retries 3
  @retry_delay 2_000

  defstruct downloads: %{}, next_id: 1

  defmodule Download do
    @moduledoc false
    defstruct [
      :id,
      :model_id,
      :model_name,
      :url,
      :target_path,
      :target_dir,
      :filename,
      :total_bytes,
      :downloaded_bytes,
      :status,
      :error,
      :start_time,
      :end_time,
      :task_ref,
      :task_pid,
      :speed_bps,
      :last_speed_update,
      :last_bytes_for_speed,
      :retries
    ]
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Start downloading a model by ID"
  def start_download(model_id, target_dir \\ nil) when is_binary(model_id) do
    GenServer.call(__MODULE__, {:start_download, model_id, target_dir})
  end

  @doc "Cancel an active download"
  def cancel_download(download_id) when is_binary(download_id) do
    GenServer.call(__MODULE__, {:cancel_download, download_id})
  end

  @doc "Get progress for a specific download"
  def get_progress(download_id) when is_binary(download_id) do
    GenServer.call(__MODULE__, {:get_progress, download_id})
  end

  @doc "List all active downloads"
  def list_active do
    GenServer.call(__MODULE__, :list_active)
  end

  @doc "List all downloads"
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:start_download, model_id, target_dir}, _from, state) do
    case Registry.get_model(model_id) do
      {:ok, model} ->
        url = Map.get(model, "download_url")

        if is_nil(url) or url == "" do
          {:reply, {:error, :no_download_url}, state}
        else
          # Validate target_dir if provided to prevent path traversal
          case validate_target_dir(target_dir) do
            {:error, reason} ->
              {:reply, {:error, reason}, state}

            :ok ->
              download_id = generate_download_id(state)
              target_path = compute_target_path(model, target_dir)
              raw_filename = Map.get(model, "filename") || extract_filename_from_url(url)

              # Sanitize filename to prevent path traversal attacks
              case PathValidator.sanitize_filename(raw_filename) do
                {:error, _, reason} ->
                  {:reply, {:error, {:invalid_filename, reason}}, state}

                filename ->
                  full_path = Path.join(target_path, filename)

                  # Check for existing partial download
                  existing_bytes = get_existing_file_size(full_path)

                  download = %Download{
                    id: download_id,
                    model_id: model_id,
                    model_name: Map.get(model, "name", model_id),
                    url: url,
                    target_path: full_path,
                    target_dir: target_path,
                    filename: filename,
                    total_bytes: Map.get(model, "size_bytes", 0),
                    downloaded_bytes: existing_bytes,
                    status: :pending,
                    start_time: DateTime.utc_now(),
                    last_speed_update: System.monotonic_time(:millisecond),
                    last_bytes_for_speed: existing_bytes,
                    retries: 0
                  }

                  File.mkdir_p!(target_path)

                  # Capture GenServer PID before spawning task
                  manager_pid = self()

                  # Start download task
                  task =
                    Task.Supervisor.async_nolink(
                      LeaxerCore.TaskSupervisor,
                      fn -> execute_download(manager_pid, download_id, download) end
                    )

                  updated_download = %{
                    download
                    | status: :downloading,
                      task_ref: task.ref,
                      task_pid: task.pid
                  }

                  new_state = %{
                    state
                    | downloads: Map.put(state.downloads, download_id, updated_download),
                      next_id: state.next_id + 1
                  }

                  broadcast(:download_started, updated_download)

                  {:reply, {:ok, download_id}, new_state}
              end
          end
        end

      {:error, :model_not_found} ->
        {:reply, {:error, :model_not_found}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:cancel_download, download_id}, _from, state) do
    case Map.get(state.downloads, download_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: status} = download when status in [:downloading, :pending] ->
        # Cancel the task by killing the process
        if download.task_pid && Process.alive?(download.task_pid) do
          Process.exit(download.task_pid, :shutdown)
        end

        updated = %{
          download
          | status: :cancelled,
            error: "Cancelled by user",
            end_time: DateTime.utc_now(),
            task_ref: nil,
            task_pid: nil
        }

        new_state = %{state | downloads: Map.put(state.downloads, download_id, updated)}
        broadcast(:download_cancelled, updated)

        {:reply, :ok, new_state}

      _ ->
        {:reply, {:error, :not_active}, state}
    end
  end

  @impl true
  def handle_call({:get_progress, download_id}, _from, state) do
    case Map.get(state.downloads, download_id) do
      nil -> {:reply, {:error, :not_found}, state}
      download -> {:reply, {:ok, build_progress_map(download)}, state}
    end
  end

  @impl true
  def handle_call(:list_active, _from, state) do
    active =
      state.downloads
      |> Map.values()
      |> Enum.filter(&(&1.status in [:pending, :downloading]))
      |> Enum.map(&build_progress_map/1)

    {:reply, {:ok, active}, state}
  end

  @impl true
  def handle_call(:list_all, _from, state) do
    all = state.downloads |> Map.values() |> Enum.map(&build_progress_map/1)
    {:reply, {:ok, all}, state}
  end

  # Handle progress messages from download task
  @impl true
  def handle_info({:download_progress, download_id, bytes, total}, state) do
    case Map.get(state.downloads, download_id) do
      nil ->
        {:noreply, state}

      download ->
        now = System.system_time(:millisecond)
        last_update = Map.get(download, :last_speed_update, now)
        last_bytes = Map.get(download, :last_bytes_for_speed, 0)
        last_broadcast = Map.get(download, :last_broadcast, 0)

        time_diff = now - last_update
        bytes_diff = bytes - last_bytes

        # Calculate speed every 500ms
        {speed, new_last_update, new_last_bytes} =
          if time_diff >= 500 do
            speed = if time_diff > 0, do: round(bytes_diff * 1000 / time_diff), else: 0
            {speed, now, bytes}
          else
            {Map.get(download, :speed_bps) || 0, last_update, last_bytes}
          end

        updated =
          Map.merge(download, %{
            downloaded_bytes: bytes,
            total_bytes: max(total, Map.get(download, :total_bytes, 0)),
            speed_bps: speed,
            last_speed_update: new_last_update,
            last_bytes_for_speed: new_last_bytes
          })

        new_state = %{state | downloads: Map.put(state.downloads, download_id, updated)}

        # Broadcast progress every @progress_interval ms
        if now - last_broadcast >= @progress_interval do
          updated_with_broadcast = Map.put(updated, :last_broadcast, now)

          new_state2 = %{
            state
            | downloads: Map.put(state.downloads, download_id, updated_with_broadcast)
          }

          broadcast(:progress_update, updated_with_broadcast)
          {:noreply, new_state2}
        else
          {:noreply, new_state}
        end
    end
  end

  # Handle task completion
  @impl true
  def handle_info({ref, :ok}, state) do
    Process.demonitor(ref, [:flush])

    case find_download_by_ref(state.downloads, ref) do
      nil ->
        {:noreply, state}

      {download_id, download} ->
        updated =
          Map.merge(download, %{
            status: :complete,
            end_time: DateTime.utc_now(),
            task_ref: nil,
            task_pid: nil,
            downloaded_bytes: download.total_bytes
          })

        new_state = %{state | downloads: Map.put(state.downloads, download_id, updated)}
        broadcast(:download_complete, updated)

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info({ref, {:error, reason}}, state) do
    Process.demonitor(ref, [:flush])

    case find_download_by_ref(state.downloads, ref) do
      nil ->
        {:noreply, state}

      {download_id, download} ->
        # Retry logic
        if download.retries < @max_retries and should_retry?(reason) do
          Logger.warning(
            "Download #{download_id} failed, retrying (#{download.retries + 1}/#{@max_retries}): #{inspect(reason)}"
          )

          Process.send_after(self(), {:retry_download, download_id}, @retry_delay)

          updated =
            Map.merge(download, %{retries: download.retries + 1, task_ref: nil, task_pid: nil})

          new_state = %{state | downloads: Map.put(state.downloads, download_id, updated)}

          {:noreply, new_state}
        else
          updated =
            Map.merge(download, %{
              status: :failed,
              error: format_error(reason),
              end_time: DateTime.utc_now(),
              task_ref: nil,
              task_pid: nil
            })

          new_state = %{state | downloads: Map.put(state.downloads, download_id, updated)}
          broadcast(:download_failed, updated)

          {:noreply, new_state}
        end
    end
  end

  # Handle task crash
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case find_download_by_ref(state.downloads, ref) do
      nil ->
        {:noreply, state}

      {download_id, download} ->
        updated =
          Map.merge(download, %{
            status: :failed,
            error: "Download process crashed: #{inspect(reason)}",
            end_time: DateTime.utc_now(),
            task_ref: nil,
            task_pid: nil
          })

        new_state = %{state | downloads: Map.put(state.downloads, download_id, updated)}
        broadcast(:download_failed, updated)

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info({:retry_download, download_id}, state) do
    case Map.get(state.downloads, download_id) do
      nil ->
        {:noreply, state}

      %{status: :cancelled} ->
        {:noreply, state}

      download ->
        manager_pid = self()

        task =
          Task.Supervisor.async_nolink(
            LeaxerCore.TaskSupervisor,
            fn -> execute_download(manager_pid, download_id, download) end
          )

        updated = %{download | task_ref: task.ref, task_pid: task.pid, status: :downloading}
        new_state = %{state | downloads: Map.put(state.downloads, download_id, updated)}

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp generate_download_id(state) do
    "dl_#{state.next_id}_#{System.system_time(:millisecond)}"
  end

  # Validate that target_dir override is within allowed models directory
  # to prevent path traversal attacks
  defp validate_target_dir(nil), do: :ok

  defp validate_target_dir(override) when is_binary(override) do
    base = Paths.models_dir()

    case PathValidator.validate_within_directory(override, base) do
      :ok -> :ok
      {:error, :path_traversal, _} -> {:error, :path_traversal}
    end
  end

  defp validate_target_dir(_), do: {:error, :invalid_target_dir}

  defp compute_target_path(model, override) do
    if override do
      override
    else
      category = Map.get(model, "category", "unknown")
      base = Paths.models_dir()

      case category do
        "checkpoints" -> Path.join(base, "checkpoint")
        "loras" -> Path.join(base, "lora")
        "vaes" -> Path.join(base, "vae")
        "controlnets" -> Path.join(base, "controlnet")
        "llms" -> Path.join(base, "llm")
        "text_encoders" -> Path.join(base, "text_encoder")
        "upscalers" -> Path.join(base, "upscaler")
        _ -> Path.join(base, "other")
      end
    end
  end

  defp extract_filename_from_url(url) do
    url
    |> URI.parse()
    |> Map.get(:path, "")
    |> Path.basename()
    |> case do
      "" -> "model_#{System.system_time(:second)}"
      name -> URI.decode(name)
    end
  end

  defp get_existing_file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end

  defp find_download_by_ref(downloads, ref) do
    Enum.find_value(downloads, fn {id, dl} ->
      if dl.task_ref == ref, do: {id, dl}
    end)
  end

  defp should_retry?(reason) do
    case reason do
      :timeout -> true
      :closed -> true
      {:error, :timeout} -> true
      {:error, :closed} -> true
      {:error, :econnreset} -> true
      _ -> false
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  # Download execution (runs in Task)
  defp execute_download(manager_pid, download_id, download) do
    url = download.url
    path = download.target_path
    total_bytes = download.total_bytes
    existing_bytes = download.downloaded_bytes

    # Build Range header for resume support
    headers =
      if existing_bytes > 0 do
        [{"Range", "bytes=#{existing_bytes}-"}]
      else
        []
      end

    # First, make a HEAD request or check if server supports Range
    # by examining the response status code
    result =
      Req.get(url,
        finch: LeaxerCore.Finch,
        raw: true,
        decode_body: false,
        headers: headers,
        into: :self,
        receive_timeout: @http_timeout,
        max_redirects: 10
      )

    case result do
      {:ok, resp} ->
        handle_download_response(
          manager_pid,
          download_id,
          resp,
          url,
          path,
          existing_bytes,
          total_bytes
        )

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, "Network error: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  # Handle the HTTP response and decide whether to resume or restart
  defp handle_download_response(
         manager_pid,
         download_id,
         resp,
         url,
         path,
         existing_bytes,
         total_bytes
       ) do
    status = resp.status

    cond do
      # 206 Partial Content - server supports Range, resume download
      status == 206 ->
        {file_mode, byte_offset} = {:append, existing_bytes}
        content_length = get_content_length(resp, total_bytes)
        actual_total = existing_bytes + content_length

        stream_download(
          manager_pid,
          download_id,
          resp,
          path,
          file_mode,
          byte_offset,
          actual_total
        )

      # 200 OK - server doesn't support Range or file changed, start fresh
      status == 200 ->
        # Server ignored Range header, need to start from beginning
        # Log if we expected to resume but couldn't
        if existing_bytes > 0 do
          Logger.info(
            "Server doesn't support resume for #{url}, restarting download from beginning"
          )
        end

        {file_mode, byte_offset} = {:write, 0}
        content_length = get_content_length(resp, total_bytes)

        stream_download(
          manager_pid,
          download_id,
          resp,
          path,
          file_mode,
          byte_offset,
          content_length
        )

      # 416 Range Not Satisfiable - file may be complete or corrupted
      status == 416 ->
        # Check if we already have the complete file
        actual_size = get_existing_file_size(path)

        if actual_size > 0 and actual_size == total_bytes do
          Logger.info("Download already complete: #{path}")
          :ok
        else
          # File is corrupted or size mismatch, restart from beginning
          Logger.warning("Range not satisfiable for #{url}, restarting download")
          restart_download_fresh(manager_pid, download_id, url, path, total_bytes)
        end

      # Other status codes - error
      true ->
        {:error, "HTTP #{status}: #{inspect(resp.body)}"}
    end
  end

  # Stream the response body to file
  defp stream_download(
         manager_pid,
         download_id,
         resp,
         path,
         file_mode,
         byte_offset,
         total_bytes
       ) do
    # Open file with correct mode: :write truncates, :append preserves
    file = File.open!(path, [file_mode, :binary])
    downloaded_ref = :counters.new(1, [:atomics])
    :counters.put(downloaded_ref, 1, byte_offset)

    # Process the response body stream
    result =
      try do
        stream_response_body(resp, fn chunk ->
          IO.binwrite(file, chunk)
          :counters.add(downloaded_ref, 1, byte_size(chunk))
          current = :counters.get(downloaded_ref, 1)
          send(manager_pid, {:download_progress, download_id, current, total_bytes})
        end)
      after
        File.close(file)
      end

    result
  end

  # Process the streaming response body
  defp stream_response_body(resp, write_fn) do
    receive_stream_chunks(resp, write_fn)
  end

  defp receive_stream_chunks(resp, write_fn) do
    receive do
      {_ref, {:data, chunk}} ->
        write_fn.(chunk)
        receive_stream_chunks(resp, write_fn)

      {_ref, :done} ->
        :ok

      {_ref, {:error, reason}} ->
        {:error, reason}
    after
      @http_timeout ->
        {:error, :timeout}
    end
  end

  # Restart download from the beginning (no Range header)
  defp restart_download_fresh(manager_pid, download_id, url, path, total_bytes) do
    result =
      Req.get(url,
        finch: LeaxerCore.Finch,
        raw: true,
        decode_body: false,
        into: :self,
        receive_timeout: @http_timeout,
        max_redirects: 10
      )

    case result do
      {:ok, resp} when resp.status == 200 ->
        content_length = get_content_length(resp, total_bytes)

        stream_download(
          manager_pid,
          download_id,
          resp,
          path,
          :write,
          0,
          content_length
        )

      {:ok, resp} ->
        {:error, "HTTP #{resp.status} on retry"}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, "Network error: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  # Extract Content-Length from response headers
  defp get_content_length(resp, default) do
    case Req.Response.get_header(resp, "content-length") do
      [len | _] -> String.to_integer(len)
      _ -> default
    end
  end

  defp build_progress_map(download) do
    total_bytes = Map.get(download, :total_bytes, 0)
    downloaded_bytes = Map.get(download, :downloaded_bytes, 0)
    start_time = Map.get(download, :start_time)
    end_time = Map.get(download, :end_time)

    percentage =
      if total_bytes > 0 do
        min(100, round(downloaded_bytes / total_bytes * 100))
      else
        0
      end

    duration =
      cond do
        end_time && start_time -> DateTime.diff(end_time, start_time, :second)
        start_time -> DateTime.diff(DateTime.utc_now(), start_time, :second)
        true -> 0
      end

    %{
      download_id: Map.get(download, :id),
      model_id: Map.get(download, :model_id),
      model_name: Map.get(download, :model_name),
      filename: Map.get(download, :filename),
      status: Map.get(download, :status),
      percentage: percentage,
      bytes_downloaded: downloaded_bytes,
      total_bytes: total_bytes,
      speed_bps: Map.get(download, :speed_bps) || 0,
      error: Map.get(download, :error),
      target_path: Map.get(download, :target_path),
      duration_seconds: duration
    }
  end

  # PubSub Broadcasting

  defp broadcast(event, download) do
    payload = build_progress_map(download)

    Phoenix.PubSub.broadcast(
      LeaxerCore.PubSub,
      "downloads:progress",
      {event, payload}
    )
  end
end
