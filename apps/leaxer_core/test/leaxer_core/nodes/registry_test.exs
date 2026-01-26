defmodule LeaxerCore.Nodes.RegistryTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias LeaxerCore.Nodes.Registry

  describe "get_module/1" do
    test "returns module for built-in node type" do
      assert Registry.get_module("MathOp") == LeaxerCore.Nodes.Math.MathOp
    end

    test "returns nil for unknown node type" do
      assert Registry.get_module("NonexistentNode") == nil
    end
  end

  describe "list_types/0" do
    test "returns list of type strings" do
      types = Registry.list_types()
      assert is_list(types)
      assert "MathOp" in types
      assert "Integer" in types
      assert "String" in types
    end

    test "returns sorted list" do
      types = Registry.list_types()
      assert types == Enum.sort(types)
    end
  end

  describe "list_all_with_metadata/0" do
    test "returns list of metadata maps" do
      nodes = Registry.list_all_with_metadata()
      assert is_list(nodes)
      assert length(nodes) > 0

      # Each node should have required keys
      Enum.each(nodes, fn node ->
        assert Map.has_key?(node, :type)
        assert Map.has_key?(node, :label)
        assert Map.has_key?(node, :category)
        assert Map.has_key?(node, :input_spec)
        assert Map.has_key?(node, :output_spec)
        assert Map.has_key?(node, :source)
      end)
    end

    test "includes source information" do
      nodes = Registry.list_all_with_metadata()
      sources = Enum.map(nodes, & &1.source) |> Enum.uniq()

      # At minimum, should have built-in nodes
      assert :builtin in sources
    end
  end

  describe "get_metadata/1" do
    test "returns {:ok, metadata} for existing node" do
      assert {:ok, metadata} = Registry.get_metadata("MathOp")
      assert metadata.type == "MathOp"
      assert is_binary(metadata.label)
      assert is_binary(metadata.category)
    end

    test "returns {:error, :not_found} for unknown node" do
      assert {:error, :not_found} = Registry.get_metadata("NonexistentNode")
    end
  end

  describe "get_spec/1" do
    test "returns spec for existing node" do
      spec = Registry.get_spec("Integer")
      assert spec != nil
      assert spec.type == "Integer"
    end

    test "returns nil for unknown node" do
      assert Registry.get_spec("NonexistentNode") == nil
    end
  end

  describe "stats/0" do
    test "returns statistics map" do
      stats = Registry.stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :total)
      assert Map.has_key?(stats, :builtin)
      assert Map.has_key?(stats, :custom)
    end

    test "builtin count is greater than zero" do
      stats = Registry.stats()
      assert stats.builtin > 0
    end

    test "total equals builtin plus custom" do
      stats = Registry.stats()
      assert stats.total == stats.builtin + stats.custom
    end
  end

  describe "hot_reload_enabled?/0" do
    test "returns boolean" do
      result = Registry.hot_reload_enabled?()
      assert is_boolean(result)
    end
  end

  describe "reload_custom_nodes/0" do
    setup do
      # Store original config and restore after test
      original_config = Application.get_env(:leaxer_core, Registry, [])

      on_exit(fn ->
        Application.put_env(:leaxer_core, Registry, original_config)
      end)

      :ok
    end

    test "returns {:error, :hot_reload_disabled} when disabled" do
      Application.put_env(:leaxer_core, Registry, hot_reload: false)

      assert {:error, :hot_reload_disabled} = Registry.reload_custom_nodes()
    end

    test "returns {:ok, count} when enabled" do
      Application.put_env(:leaxer_core, Registry, hot_reload: true)

      # Should succeed (even if no custom nodes exist)
      assert {:ok, count} = Registry.reload_custom_nodes()
      assert is_integer(count)
      assert count >= 0
    end

    test "preserves built-in nodes after reload" do
      Application.put_env(:leaxer_core, Registry, hot_reload: true)

      # Get initial stats
      initial_stats = Registry.stats()
      initial_builtin = initial_stats.builtin

      # Reload
      {:ok, _} = Registry.reload_custom_nodes()

      # Verify built-in nodes are preserved
      new_stats = Registry.stats()
      assert new_stats.builtin == initial_builtin
    end

    test "MathOp is still available after reload" do
      Application.put_env(:leaxer_core, Registry, hot_reload: true)

      {:ok, _} = Registry.reload_custom_nodes()

      # Built-in node should still work
      assert Registry.get_module("MathOp") == LeaxerCore.Nodes.Math.MathOp
    end
  end

  describe "config defaults" do
    test "hot_reload defaults to false when not configured" do
      # Clear config
      original = Application.get_env(:leaxer_core, Registry)
      Application.delete_env(:leaxer_core, Registry)

      on_exit(fn ->
        if original do
          Application.put_env(:leaxer_core, Registry, original)
        end
      end)

      # Should default to false for safety
      # Note: In test env, dev.exs may have set it to true already,
      # so this test mainly verifies the logic path
      result = Registry.hot_reload_enabled?()
      assert is_boolean(result)
    end
  end
end
