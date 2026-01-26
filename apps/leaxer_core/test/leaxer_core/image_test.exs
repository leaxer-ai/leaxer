defmodule LeaxerCore.ImageTest do
  use ExUnit.Case, async: true

  alias LeaxerCore.Image

  describe "extract_path/1" do
    test "extracts path from map with atom key" do
      assert Image.extract_path(%{path: "/tmp/test.png"}) == "/tmp/test.png"
    end

    test "extracts path from map with string key" do
      assert Image.extract_path(%{"path" => "/tmp/test.png"}) == "/tmp/test.png"
    end

    test "returns nil for map without path" do
      assert Image.extract_path(%{data: "base64..."}) == nil
    end

    test "returns nil for non-map" do
      assert Image.extract_path("string") == nil
      assert Image.extract_path(123) == nil
      assert Image.extract_path(nil) == nil
    end
  end

  describe "extract_base64_data/1" do
    test "extracts data and mime_type from map with atom keys" do
      image = %{data: "base64data", mime_type: "image/png"}
      assert Image.extract_base64_data(image) == {"base64data", "image/png"}
    end

    test "extracts data and mime_type from map with string keys" do
      image = %{"data" => "base64data", "mime_type" => "image/png"}
      assert Image.extract_base64_data(image) == {"base64data", "image/png"}
    end

    test "returns nil if data is missing" do
      assert Image.extract_base64_data(%{mime_type: "image/png"}) == nil
    end

    test "returns nil if mime_type is missing" do
      assert Image.extract_base64_data(%{data: "base64data"}) == nil
    end

    test "returns nil for non-map" do
      assert Image.extract_base64_data("string") == nil
      assert Image.extract_base64_data(nil) == nil
    end
  end

  describe "base64?/1" do
    test "returns true for base64 format image" do
      assert Image.base64?(%{data: "abc", mime_type: "image/png"}) == true
    end

    test "returns false for path format image" do
      assert Image.base64?(%{path: "/tmp/test.png"}) == false
    end

    test "returns false for non-map" do
      assert Image.base64?(nil) == false
    end
  end

  describe "path?/1" do
    test "returns true for path format image" do
      assert Image.path?(%{path: "/tmp/test.png"}) == true
    end

    test "returns false for base64 format image" do
      assert Image.path?(%{data: "abc", mime_type: "image/png"}) == false
    end

    test "returns false for non-map" do
      assert Image.path?(nil) == false
    end
  end

  describe "to_display_url/1" do
    test "returns data URL for base64 format" do
      image = %{data: "dGVzdA==", mime_type: "image/png"}
      {:ok, url} = Image.to_display_url(image)
      assert url == "data:image/png;base64,dGVzdA=="
    end

    test "returns HTTP URL for path in tmp_dir" do
      tmp_dir = LeaxerCore.Paths.tmp_dir()
      path = Path.join(tmp_dir, "test.png")
      image = %{path: path}

      {:ok, url} = Image.to_display_url(image)
      assert String.starts_with?(url, "/api/tmp/test.png?t=")
    end

    test "returns HTTP URL for path in outputs_dir" do
      outputs_dir = LeaxerCore.Paths.outputs_dir()
      path = Path.join(outputs_dir, "saved.png")
      image = %{path: path}

      {:ok, url} = Image.to_display_url(image)
      assert String.starts_with?(url, "/api/outputs/saved.png?t=")
    end

    test "returns error for invalid image" do
      assert {:error, _} = Image.to_display_url(%{})
      assert {:error, _} = Image.to_display_url(nil)
    end
  end

  describe "extract_path_or_materialize/1" do
    test "returns path directly when present" do
      image = %{path: "/tmp/existing.png"}
      assert {:ok, "/tmp/existing.png"} = Image.extract_path_or_materialize(image)
    end

    test "materializes base64 data to disk when no path" do
      # Create a minimal valid PNG (1x1 transparent pixel)
      png_base64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

      image = %{data: png_base64, mime_type: "image/png"}

      assert {:ok, path} = Image.extract_path_or_materialize(image)
      assert String.contains?(path, "materialized_")
      assert File.exists?(path)

      # Cleanup
      File.rm(path)
    end

    test "returns error for invalid base64 data" do
      image = %{data: "not-valid-base64!!!", mime_type: "image/png"}
      assert {:error, _} = Image.extract_path_or_materialize(image)
    end

    test "returns error for empty image" do
      assert {:error, _} = Image.extract_path_or_materialize(%{})
    end
  end
end
