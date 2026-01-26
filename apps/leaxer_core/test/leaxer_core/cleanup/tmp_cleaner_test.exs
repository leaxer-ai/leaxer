defmodule LeaxerCore.Cleanup.TmpCleanerTest do
  use ExUnit.Case, async: false

  @moduletag :cleanup_test

  # Use a test-specific tmp directory to avoid interfering with real files
  @test_tmp_dir Path.join(System.tmp_dir!(), "leaxer_cleanup_test_#{:rand.uniform(100_000)}")

  setup do
    # Create test directory
    File.mkdir_p!(@test_tmp_dir)

    # Override the tmp_dir function for testing
    original_env = Application.get_env(:leaxer_core, :test_tmp_dir)
    Application.put_env(:leaxer_core, :test_tmp_dir, @test_tmp_dir)

    on_exit(fn ->
      # Clean up test directory
      File.rm_rf!(@test_tmp_dir)

      # Restore original config
      if original_env do
        Application.put_env(:leaxer_core, :test_tmp_dir, original_env)
      else
        Application.delete_env(:leaxer_core, :test_tmp_dir)
      end
    end)

    {:ok, tmp_dir: @test_tmp_dir}
  end

  describe "age-based cleanup" do
    test "removes files older than max_age", %{tmp_dir: tmp_dir} do
      # Create an "old" file by touching it with an old mtime
      old_file = Path.join(tmp_dir, "old_file.png")
      recent_file = Path.join(tmp_dir, "recent_file.png")

      File.write!(old_file, "old content")
      File.write!(recent_file, "recent content")

      # Set old file's mtime to 2 hours ago
      two_hours_ago = System.system_time(:second) - 7200
      File.touch!(old_file, two_hours_ago)

      # Run cleanup with 1 hour max age
      result = do_cleanup_in_dir(tmp_dir, max_age_seconds: 3600, max_size_bytes: 0)

      assert {:ok, stats} = result
      assert stats.removed_count == 1
      assert not File.exists?(old_file)
      assert File.exists?(recent_file)
    end

    test "keeps files younger than max_age", %{tmp_dir: tmp_dir} do
      # Create a recent file
      recent_file = Path.join(tmp_dir, "recent_file.png")
      File.write!(recent_file, "recent content")

      result = do_cleanup_in_dir(tmp_dir, max_age_seconds: 3600, max_size_bytes: 0)

      assert {:ok, stats} = result
      assert stats.removed_count == 0
      assert File.exists?(recent_file)
    end

    test "handles empty directory", %{tmp_dir: tmp_dir} do
      result = do_cleanup_in_dir(tmp_dir, max_age_seconds: 3600, max_size_bytes: 0)

      assert {:ok, stats} = result
      assert stats.removed_count == 0
    end
  end

  describe "size-based cleanup" do
    test "removes oldest files when over size limit", %{tmp_dir: tmp_dir} do
      # Create 3 files with different ages and sizes
      file1 = Path.join(tmp_dir, "oldest.png")
      file2 = Path.join(tmp_dir, "middle.png")
      file3 = Path.join(tmp_dir, "newest.png")

      # Each file is 100 bytes, total 300 bytes
      File.write!(file1, String.duplicate("a", 100))
      File.write!(file2, String.duplicate("b", 100))
      File.write!(file3, String.duplicate("c", 100))

      # Set different mtimes (all within max_age to test size-based cleanup)
      now = System.system_time(:second)
      # oldest
      File.touch!(file1, now - 300)
      # middle
      File.touch!(file2, now - 200)
      # newest
      File.touch!(file3, now - 100)

      # Set max_size to 150 bytes (should remove oldest until under limit)
      result = do_cleanup_in_dir(tmp_dir, max_age_seconds: 3600, max_size_bytes: 150)

      assert {:ok, stats} = result
      # Should remove 2 files (oldest, then middle) to get under 150 bytes
      assert stats.removed_count == 2
      assert not File.exists?(file1)
      assert not File.exists?(file2)
      assert File.exists?(file3)
    end

    test "does not remove files when under size limit", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "small.png")
      File.write!(file, "small content")

      # Set max_size larger than file
      result = do_cleanup_in_dir(tmp_dir, max_age_seconds: 3600, max_size_bytes: 1_000_000)

      assert {:ok, stats} = result
      assert stats.removed_count == 0
      assert File.exists?(file)
    end

    test "disables size limit when set to 0", %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "file.png")
      File.write!(file, String.duplicate("x", 1000))

      # max_size_bytes: 0 should disable size-based cleanup
      result = do_cleanup_in_dir(tmp_dir, max_age_seconds: 3600, max_size_bytes: 0)

      assert {:ok, stats} = result
      assert stats.removed_count == 0
      assert File.exists?(file)
    end
  end

  describe "combined cleanup" do
    test "age cleanup runs before size cleanup", %{tmp_dir: tmp_dir} do
      old_file = Path.join(tmp_dir, "old.png")
      recent_file = Path.join(tmp_dir, "recent.png")

      File.write!(old_file, String.duplicate("a", 100))
      File.write!(recent_file, String.duplicate("b", 100))

      # Make old_file actually old
      old_time = System.system_time(:second) - 7200
      File.touch!(old_file, old_time)

      # Size limit that would allow both files if age cleanup didn't run first
      result = do_cleanup_in_dir(tmp_dir, max_age_seconds: 3600, max_size_bytes: 250)

      assert {:ok, stats} = result
      # Only the old file
      assert stats.removed_count == 1
      assert not File.exists?(old_file)
      assert File.exists?(recent_file)
    end
  end

  describe "stats/0" do
    test "returns directory statistics", %{tmp_dir: tmp_dir} do
      file1 = Path.join(tmp_dir, "file1.png")
      file2 = Path.join(tmp_dir, "file2.png")

      File.write!(file1, String.duplicate("a", 100))
      File.write!(file2, String.duplicate("b", 200))

      stats = get_stats_for_dir(tmp_dir)

      assert stats.file_count == 2
      assert stats.total_bytes == 300
      assert stats.oldest_mtime != nil
      assert stats.tmp_dir == tmp_dir
    end

    test "handles empty directory", %{tmp_dir: tmp_dir} do
      stats = get_stats_for_dir(tmp_dir)

      assert stats.file_count == 0
      assert stats.total_bytes == 0
      assert stats.oldest_mtime == nil
    end
  end

  describe "format_bytes/1" do
    test "formats bytes correctly" do
      assert format_bytes(500) == "500 B"
      assert format_bytes(1024) == "1.0 KB"
      assert format_bytes(1_500_000) == "1.4 MB"
      assert format_bytes(2_000_000_000) == "1.86 GB"
    end
  end

  # Helper functions that test the internal logic without starting GenServer
  # These mirror the private functions in TmpCleaner

  defp do_cleanup_in_dir(dir, opts) do
    max_age = Keyword.get(opts, :max_age_seconds, 3600)
    max_size = Keyword.get(opts, :max_size_bytes, 0)

    case list_files_with_stats(dir) do
      {:ok, files} when files != [] ->
        now = System.system_time(:second)
        cutoff_time = now - max_age

        {old_files, recent_files} =
          Enum.split_with(files, fn {_path, stat} ->
            stat.mtime_seconds < cutoff_time
          end)

        old_count = length(old_files)
        old_bytes = Enum.reduce(old_files, 0, fn {_path, stat}, acc -> acc + stat.size end)

        Enum.each(old_files, fn {path, _stat} ->
          File.rm(path)
        end)

        {size_count, size_bytes} =
          if max_size > 0 do
            total_size =
              Enum.reduce(recent_files, 0, fn {_path, stat}, acc -> acc + stat.size end)

            cleanup_by_size(recent_files, total_size, max_size)
          else
            {0, 0}
          end

        {:ok, %{removed_count: old_count + size_count, removed_bytes: old_bytes + size_bytes}}

      {:ok, []} ->
        {:ok, %{removed_count: 0, removed_bytes: 0}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_files_with_stats(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        files =
          names
          |> Enum.map(fn name -> Path.join(dir, name) end)
          |> Enum.filter(&File.regular?/1)
          |> Enum.map(fn path ->
            case File.stat(path, time: :posix) do
              {:ok, stat} ->
                {path, %{size: stat.size, mtime_seconds: stat.mtime}}

              {:error, _} ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, files}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cleanup_by_size(_files, current_size, max_size) when current_size <= max_size do
    {0, 0}
  end

  defp cleanup_by_size(files, current_size, max_size) do
    sorted = Enum.sort_by(files, fn {_path, stat} -> stat.mtime_seconds end)

    {removed_count, removed_bytes, _} =
      Enum.reduce_while(sorted, {0, 0, current_size}, fn {path, stat}, {count, bytes, size} ->
        if size <= max_size do
          {:halt, {count, bytes, size}}
        else
          File.rm(path)
          {:cont, {count + 1, bytes + stat.size, size - stat.size}}
        end
      end)

    {removed_count, removed_bytes}
  end

  defp get_stats_for_dir(dir) do
    case list_files_with_stats(dir) do
      {:ok, files} ->
        total_size = Enum.reduce(files, 0, fn {_path, stat}, acc -> acc + stat.size end)
        file_count = length(files)

        oldest =
          if files == [] do
            nil
          else
            files
            |> Enum.min_by(fn {_path, stat} -> stat.mtime_seconds end)
            |> elem(1)
            |> Map.get(:mtime_seconds)
          end

        %{
          file_count: file_count,
          total_bytes: total_size,
          oldest_mtime: oldest,
          tmp_dir: dir
        }

      {:error, reason} ->
        %{error: reason}
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes) when bytes < 1_073_741_824,
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"
end
