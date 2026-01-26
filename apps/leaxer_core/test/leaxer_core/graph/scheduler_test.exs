defmodule LeaxerCore.Graph.SchedulerTest do
  use ExUnit.Case, async: true

  alias LeaxerCore.Graph.Scheduler

  describe "schedule_flat/2" do
    test "returns valid topological order for linear chain" do
      # A -> B -> C
      nodes = %{
        "node_1000_a" => %{},
        "node_2000_b" => %{},
        "node_3000_c" => %{}
      }

      edges = [
        %{"source" => "node_1000_a", "target" => "node_2000_b"},
        %{"source" => "node_2000_b", "target" => "node_3000_c"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      assert sorted == ["node_1000_a", "node_2000_b", "node_3000_c"]
    end

    test "independent nodes sorted by depth then timestamp" do
      # Three independent nodes - all are output nodes (depth 1)
      # Among equal depths, sorted by timestamp descending
      nodes = %{
        "node_3000_c" => %{},
        "node_1000_a" => %{},
        "node_2000_b" => %{}
      }

      edges = []

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # All depth 1, so fall back to timestamp descending
      assert sorted == ["node_3000_c", "node_2000_b", "node_1000_a"]
    end

    test "preview node executes immediately when ready (shallower first)" do
      # gen -> upscale -> preview_upscaled
      # gen -> preview_gen
      #
      # When gen completes, both upscale (depth 2) and preview_gen (depth 1) become ready
      # preview_gen should execute FIRST because it's shallower (closer to output)
      nodes = %{
        "node_1000_gen" => %{},
        "node_2000_upscale" => %{},
        "node_3000_preview_up" => %{},
        "node_4000_preview_gen" => %{}
      }

      edges = [
        %{"source" => "node_1000_gen", "target" => "node_2000_upscale"},
        %{"source" => "node_2000_upscale", "target" => "node_3000_preview_up"},
        %{"source" => "node_1000_gen", "target" => "node_4000_preview_gen"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # Depths: gen=3, upscale=2, preview_up=1, preview_gen=1
      # Execute shallower nodes first when they become ready
      assert sorted == [
               "node_1000_gen",
               "node_4000_preview_gen",
               "node_2000_upscale",
               "node_3000_preview_up"
             ]
    end

    test "branching: shallower branch (preview) executes first" do
      # A -> B -> C (deeper branch)
      # A -> D (shallower branch, D is output)
      # When A completes, D should execute before B
      nodes = %{
        "node_1000_a" => %{},
        "node_2000_b" => %{},
        "node_3000_c" => %{},
        "node_4000_d" => %{}
      }

      edges = [
        %{"source" => "node_1000_a", "target" => "node_2000_b"},
        %{"source" => "node_2000_b", "target" => "node_3000_c"},
        %{"source" => "node_1000_a", "target" => "node_4000_d"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # Depths: a=3, b=2, c=1, d=1
      # A executes first, then D (depth 1) before B (depth 2)
      assert hd(sorted) == "node_1000_a"
      assert Enum.at(sorted, 1) == "node_4000_d"
      assert Enum.at(sorted, 2) == "node_2000_b"
      assert Enum.at(sorted, 3) == "node_3000_c"
    end

    test "detects cycle" do
      # A -> B -> C -> A (cycle)
      nodes = %{
        "node_1000_a" => %{},
        "node_2000_b" => %{},
        "node_3000_c" => %{}
      }

      edges = [
        %{"source" => "node_1000_a", "target" => "node_2000_b"},
        %{"source" => "node_2000_b", "target" => "node_3000_c"},
        %{"source" => "node_3000_c", "target" => "node_1000_a"}
      ]

      assert {:error, :cycle_detected, %{}} = Scheduler.schedule_flat(nodes, edges)
    end

    test "handles disconnected subgraphs" do
      # Subgraph 1: A -> B (depths: A=2, B=1)
      # Subgraph 2: C -> D (depths: C=2, D=1)
      nodes = %{
        "node_1000_a" => %{},
        "node_2000_b" => %{},
        "node_1500_c" => %{},
        "node_2500_d" => %{}
      }

      edges = [
        %{"source" => "node_1000_a", "target" => "node_2000_b"},
        %{"source" => "node_1500_c", "target" => "node_2500_d"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # A must come before B (topological constraint)
      assert Enum.find_index(sorted, &(&1 == "node_1000_a")) <
               Enum.find_index(sorted, &(&1 == "node_2000_b"))

      # C must come before D (topological constraint)
      assert Enum.find_index(sorted, &(&1 == "node_1500_c")) <
               Enum.find_index(sorted, &(&1 == "node_2500_d"))

      # All nodes should be present
      assert length(sorted) == 4
    end

    test "handles empty graph" do
      nodes = %{}
      edges = []

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      assert sorted == []
    end

    test "handles single node" do
      nodes = %{"node_1000_x" => %{}}
      edges = []

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      assert sorted == ["node_1000_x"]
    end

    test "handles nodes with non-standard id format" do
      # Nodes without timestamp format get timestamp 0
      nodes = %{
        "custom_id" => %{},
        "node_1000_a" => %{}
      }

      edges = []

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # Both have depth 1 (no edges), so sort by timestamp desc
      # node_1000_a has timestamp 1000, custom_id gets 0
      assert hd(sorted) == "node_1000_a"
      assert Enum.at(sorted, 1) == "custom_id"
    end

    test "preview node executes before continuing deeper branch" do
      # Simulates: GenerateImage -> PreviewImage (shallow branch, depth 1)
      #            GenerateImage -> SDUpscaler -> PreviewImage2 (deeper branch)
      # PreviewImage should execute BEFORE SDUpscaler when GenerateImage completes
      nodes = %{
        "node_1000_gen" => %{},
        "node_2000_upscale" => %{},
        "node_3000_preview1" => %{},
        "node_4000_preview2" => %{}
      }

      edges = [
        %{"source" => "node_1000_gen", "target" => "node_2000_upscale"},
        %{"source" => "node_1000_gen", "target" => "node_3000_preview1"},
        %{"source" => "node_2000_upscale", "target" => "node_4000_preview2"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # Depths: gen=3, upscale=2, preview1=1, preview2=1
      # gen executes first (root node)
      assert hd(sorted) == "node_1000_gen"

      # When gen completes, both upscale (depth 2) and preview1 (depth 1) become ready
      # preview1 is shallower, so it executes first
      assert Enum.at(sorted, 1) == "node_3000_preview1"
      assert Enum.at(sorted, 2) == "node_2000_upscale"
      assert Enum.at(sorted, 3) == "node_4000_preview2"
    end

    test "diamond dependency pattern" do
      #     A
      #    / \
      #   B   C
      #    \ /
      #     D
      nodes = %{
        "node_1000_a" => %{},
        "node_2000_b" => %{},
        "node_3000_c" => %{},
        "node_4000_d" => %{}
      }

      edges = [
        %{"source" => "node_1000_a", "target" => "node_2000_b"},
        %{"source" => "node_1000_a", "target" => "node_3000_c"},
        %{"source" => "node_2000_b", "target" => "node_4000_d"},
        %{"source" => "node_3000_c", "target" => "node_4000_d"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # Depths: A=3, B=2, C=2, D=1
      # A must be first (only root node)
      assert hd(sorted) == "node_1000_a"
      # D must be last (depends on both B and C)
      assert List.last(sorted) == "node_4000_d"
      # B and C both have depth 2, C has higher timestamp (3000 > 2000)
      assert Enum.at(sorted, 1) == "node_3000_c"
      assert Enum.at(sorted, 2) == "node_2000_b"
    end

    test "complex multi-branch workflow prioritizes outputs" do
      # LoadImage -> ProcessA -> PreviewA (branch 1)
      # LoadImage -> ProcessB -> ProcessC -> PreviewC (branch 2, deeper)
      # LoadImage -> PreviewLoad (branch 3, shallowest from load)
      nodes = %{
        "node_1000_load" => %{},
        "node_2000_procA" => %{},
        "node_3000_prevA" => %{},
        "node_4000_procB" => %{},
        "node_5000_procC" => %{},
        "node_6000_prevC" => %{},
        "node_7000_prevLoad" => %{}
      }

      edges = [
        # Branch 1
        %{"source" => "node_1000_load", "target" => "node_2000_procA"},
        %{"source" => "node_2000_procA", "target" => "node_3000_prevA"},
        # Branch 2 (deeper)
        %{"source" => "node_1000_load", "target" => "node_4000_procB"},
        %{"source" => "node_4000_procB", "target" => "node_5000_procC"},
        %{"source" => "node_5000_procC", "target" => "node_6000_prevC"},
        # Branch 3 (shallow)
        %{"source" => "node_1000_load", "target" => "node_7000_prevLoad"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # Depths: load=4, procA=2, prevA=1, procB=3, procC=2, prevC=1, prevLoad=1
      assert hd(sorted) == "node_1000_load"

      # After load: procA(2), procB(3), prevLoad(1) become ready
      # prevLoad is shallowest (1), so executes first
      assert Enum.at(sorted, 1) == "node_7000_prevLoad"

      # Verify all nodes present and topologically valid
      assert length(sorted) == 7

      # Verify topological constraints
      load_idx = Enum.find_index(sorted, &(&1 == "node_1000_load"))
      procA_idx = Enum.find_index(sorted, &(&1 == "node_2000_procA"))
      prevA_idx = Enum.find_index(sorted, &(&1 == "node_3000_prevA"))
      procB_idx = Enum.find_index(sorted, &(&1 == "node_4000_procB"))
      procC_idx = Enum.find_index(sorted, &(&1 == "node_5000_procC"))
      prevC_idx = Enum.find_index(sorted, &(&1 == "node_6000_prevC"))
      prevLoad_idx = Enum.find_index(sorted, &(&1 == "node_7000_prevLoad"))

      assert load_idx < procA_idx
      assert procA_idx < prevA_idx
      assert load_idx < procB_idx
      assert procB_idx < procC_idx
      assert procC_idx < prevC_idx
      assert load_idx < prevLoad_idx
    end

    test "real workflow: GenerateImage -> Preview vs GenerateImage -> SDUpscaler -> Preview" do
      # This mirrors the actual user workflow:
      # Gen1 -> Preview1 (user wants to see result immediately)
      # Gen1 -> Gen2 (img2img) -> Preview2 (user wants to see this too)
      # Gen2 -> SDUpscaler -> Preview3 (deeper processing)
      nodes = %{
        "node_1000_gen1" => %{},
        "node_2000_preview1" => %{},
        "node_3000_gen2" => %{},
        "node_4000_preview2" => %{},
        "node_5000_upscaler" => %{},
        "node_6000_preview3" => %{}
      }

      edges = [
        %{"source" => "node_1000_gen1", "target" => "node_2000_preview1"},
        %{"source" => "node_1000_gen1", "target" => "node_3000_gen2"},
        %{"source" => "node_3000_gen2", "target" => "node_4000_preview2"},
        %{"source" => "node_3000_gen2", "target" => "node_5000_upscaler"},
        %{"source" => "node_5000_upscaler", "target" => "node_6000_preview3"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # Depths: gen1=4, preview1=1, gen2=3, preview2=1, upscaler=2, preview3=1

      # gen1 first
      assert Enum.at(sorted, 0) == "node_1000_gen1"

      # After gen1: preview1 (depth 1) and gen2 (depth 3) ready
      # preview1 should execute first (shallower)
      assert Enum.at(sorted, 1) == "node_2000_preview1"
      assert Enum.at(sorted, 2) == "node_3000_gen2"

      # After gen2: preview2 (depth 1) and upscaler (depth 2) ready
      # preview2 should execute first (shallower)
      assert Enum.at(sorted, 3) == "node_4000_preview2"
      assert Enum.at(sorted, 4) == "node_5000_upscaler"
      assert Enum.at(sorted, 5) == "node_6000_preview3"
    end

    # === Additional Edge Case Tests ===

    test "detects self-loop cycle" do
      # A -> A (node connected to itself)
      nodes = %{"node_1000_a" => %{}}
      edges = [%{"source" => "node_1000_a", "target" => "node_1000_a"}]

      assert {:error, :cycle_detected, %{}} = Scheduler.schedule_flat(nodes, edges)
    end

    test "detects two-node cycle" do
      # A -> B -> A
      nodes = %{
        "node_1000_a" => %{},
        "node_2000_b" => %{}
      }

      edges = [
        %{"source" => "node_1000_a", "target" => "node_2000_b"},
        %{"source" => "node_2000_b", "target" => "node_1000_a"}
      ]

      assert {:error, :cycle_detected, %{}} = Scheduler.schedule_flat(nodes, edges)
    end

    test "detects cycle in larger graph with non-cyclic nodes" do
      # A -> B (valid)
      # C -> D -> E -> C (cycle)
      # F -> G (valid)
      nodes = %{
        "node_1000_a" => %{},
        "node_2000_b" => %{},
        "node_3000_c" => %{},
        "node_4000_d" => %{},
        "node_5000_e" => %{},
        "node_6000_f" => %{},
        "node_7000_g" => %{}
      }

      edges = [
        %{"source" => "node_1000_a", "target" => "node_2000_b"},
        %{"source" => "node_3000_c", "target" => "node_4000_d"},
        %{"source" => "node_4000_d", "target" => "node_5000_e"},
        %{"source" => "node_5000_e", "target" => "node_3000_c"},
        %{"source" => "node_6000_f", "target" => "node_7000_g"}
      ]

      # Should detect cycle even though some subgraphs are valid
      assert {:error, :cycle_detected, %{}} = Scheduler.schedule_flat(nodes, edges)
    end

    test "handles wide fan-out (one source, many targets)" do
      # A -> B, A -> C, A -> D, A -> E, A -> F
      nodes = %{
        "node_1000_a" => %{},
        "node_2000_b" => %{},
        "node_3000_c" => %{},
        "node_4000_d" => %{},
        "node_5000_e" => %{},
        "node_6000_f" => %{}
      }

      edges = [
        %{"source" => "node_1000_a", "target" => "node_2000_b"},
        %{"source" => "node_1000_a", "target" => "node_3000_c"},
        %{"source" => "node_1000_a", "target" => "node_4000_d"},
        %{"source" => "node_1000_a", "target" => "node_5000_e"},
        %{"source" => "node_1000_a", "target" => "node_6000_f"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # A must be first (only root node with in_degree 0)
      assert hd(sorted) == "node_1000_a"

      # All other nodes should follow (all depth 1, sorted by timestamp desc)
      assert length(sorted) == 6
      # Remaining nodes sorted by timestamp descending: f, e, d, c, b
      assert Enum.slice(sorted, 1, 5) == [
               "node_6000_f",
               "node_5000_e",
               "node_4000_d",
               "node_3000_c",
               "node_2000_b"
             ]
    end

    test "handles wide fan-in (many sources, one target)" do
      # A, B, C, D all -> E
      nodes = %{
        "node_1000_a" => %{},
        "node_2000_b" => %{},
        "node_3000_c" => %{},
        "node_4000_d" => %{},
        "node_5000_e" => %{}
      }

      edges = [
        %{"source" => "node_1000_a", "target" => "node_5000_e"},
        %{"source" => "node_2000_b", "target" => "node_5000_e"},
        %{"source" => "node_3000_c", "target" => "node_5000_e"},
        %{"source" => "node_4000_d", "target" => "node_5000_e"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # E must be last (depends on all others, in_degree 4)
      assert List.last(sorted) == "node_5000_e"

      # All source nodes should come before E (all depth 2, sorted by timestamp desc)
      assert Enum.slice(sorted, 0, 4) == [
               "node_4000_d",
               "node_3000_c",
               "node_2000_b",
               "node_1000_a"
             ]
    end

    test "handles long linear chain (10 nodes)" do
      # node_1 -> node_2 -> node_3 -> ... -> node_10
      nodes =
        1..10
        |> Enum.map(fn i -> {"node_#{i * 1000}_n#{i}", %{}} end)
        |> Map.new()

      edges =
        1..9
        |> Enum.map(fn i ->
          %{
            "source" => "node_#{i * 1000}_n#{i}",
            "target" => "node_#{(i + 1) * 1000}_n#{i + 1}"
          }
        end)

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # Must be in exact order 1 through 10
      expected = Enum.map(1..10, fn i -> "node_#{i * 1000}_n#{i}" end)
      assert sorted == expected
    end

    test "handles multiple disconnected subgraphs (3 independent chains)" do
      # Chain 1: A1 -> A2 -> A3
      # Chain 2: B1 -> B2
      # Chain 3: C1
      nodes = %{
        "node_1000_a1" => %{},
        "node_2000_a2" => %{},
        "node_3000_a3" => %{},
        "node_1500_b1" => %{},
        "node_2500_b2" => %{},
        "node_1800_c1" => %{}
      }

      edges = [
        %{"source" => "node_1000_a1", "target" => "node_2000_a2"},
        %{"source" => "node_2000_a2", "target" => "node_3000_a3"},
        %{"source" => "node_1500_b1", "target" => "node_2500_b2"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # All 6 nodes should be present
      assert length(sorted) == 6

      # Verify topological constraints within each chain
      a1_idx = Enum.find_index(sorted, &(&1 == "node_1000_a1"))
      a2_idx = Enum.find_index(sorted, &(&1 == "node_2000_a2"))
      a3_idx = Enum.find_index(sorted, &(&1 == "node_3000_a3"))
      b1_idx = Enum.find_index(sorted, &(&1 == "node_1500_b1"))
      b2_idx = Enum.find_index(sorted, &(&1 == "node_2500_b2"))

      assert a1_idx < a2_idx
      assert a2_idx < a3_idx
      assert b1_idx < b2_idx
    end

    test "handles nested diamond pattern" do
      #       A
      #      / \
      #     B   C
      #    / \ / \
      #   D   E   F
      #    \ | /
      #      G
      nodes = %{
        "node_1000_a" => %{},
        "node_2000_b" => %{},
        "node_3000_c" => %{},
        "node_4000_d" => %{},
        "node_5000_e" => %{},
        "node_6000_f" => %{},
        "node_7000_g" => %{}
      }

      edges = [
        %{"source" => "node_1000_a", "target" => "node_2000_b"},
        %{"source" => "node_1000_a", "target" => "node_3000_c"},
        %{"source" => "node_2000_b", "target" => "node_4000_d"},
        %{"source" => "node_2000_b", "target" => "node_5000_e"},
        %{"source" => "node_3000_c", "target" => "node_5000_e"},
        %{"source" => "node_3000_c", "target" => "node_6000_f"},
        %{"source" => "node_4000_d", "target" => "node_7000_g"},
        %{"source" => "node_5000_e", "target" => "node_7000_g"},
        %{"source" => "node_6000_f", "target" => "node_7000_g"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # A must be first, G must be last
      assert hd(sorted) == "node_1000_a"
      assert List.last(sorted) == "node_7000_g"

      # Verify all topological constraints
      a_idx = Enum.find_index(sorted, &(&1 == "node_1000_a"))
      b_idx = Enum.find_index(sorted, &(&1 == "node_2000_b"))
      c_idx = Enum.find_index(sorted, &(&1 == "node_3000_c"))
      d_idx = Enum.find_index(sorted, &(&1 == "node_4000_d"))
      e_idx = Enum.find_index(sorted, &(&1 == "node_5000_e"))
      f_idx = Enum.find_index(sorted, &(&1 == "node_6000_f"))
      g_idx = Enum.find_index(sorted, &(&1 == "node_7000_g"))

      # Direct edges
      assert a_idx < b_idx
      assert a_idx < c_idx
      assert b_idx < d_idx
      assert b_idx < e_idx
      assert c_idx < e_idx
      assert c_idx < f_idx
      assert d_idx < g_idx
      assert e_idx < g_idx
      assert f_idx < g_idx
    end

    test "handles parallel diamonds" do
      #   A       E
      #  / \     / \
      # B   C   F   G
      #  \ /     \ /
      #   D       H
      nodes = %{
        "node_1000_a" => %{},
        "node_2000_b" => %{},
        "node_3000_c" => %{},
        "node_4000_d" => %{},
        "node_5000_e" => %{},
        "node_6000_f" => %{},
        "node_7000_g" => %{},
        "node_8000_h" => %{}
      }

      edges = [
        # Diamond 1
        %{"source" => "node_1000_a", "target" => "node_2000_b"},
        %{"source" => "node_1000_a", "target" => "node_3000_c"},
        %{"source" => "node_2000_b", "target" => "node_4000_d"},
        %{"source" => "node_3000_c", "target" => "node_4000_d"},
        # Diamond 2
        %{"source" => "node_5000_e", "target" => "node_6000_f"},
        %{"source" => "node_5000_e", "target" => "node_7000_g"},
        %{"source" => "node_6000_f", "target" => "node_8000_h"},
        %{"source" => "node_7000_g", "target" => "node_8000_h"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # All 8 nodes
      assert length(sorted) == 8

      # Verify diamond 1 constraints
      a_idx = Enum.find_index(sorted, &(&1 == "node_1000_a"))
      b_idx = Enum.find_index(sorted, &(&1 == "node_2000_b"))
      c_idx = Enum.find_index(sorted, &(&1 == "node_3000_c"))
      d_idx = Enum.find_index(sorted, &(&1 == "node_4000_d"))

      assert a_idx < b_idx
      assert a_idx < c_idx
      assert b_idx < d_idx
      assert c_idx < d_idx

      # Verify diamond 2 constraints
      e_idx = Enum.find_index(sorted, &(&1 == "node_5000_e"))
      f_idx = Enum.find_index(sorted, &(&1 == "node_6000_f"))
      g_idx = Enum.find_index(sorted, &(&1 == "node_7000_g"))
      h_idx = Enum.find_index(sorted, &(&1 == "node_8000_h"))

      assert e_idx < f_idx
      assert e_idx < g_idx
      assert f_idx < h_idx
      assert g_idx < h_idx
    end

    test "depth tiebreaker uses timestamp correctly for nodes with same depth" do
      # Three independent chains of same length -> same depths
      # A1(1000) -> A2(4000)   depth: A1=2, A2=1
      # B1(2000) -> B2(5000)   depth: B1=2, B2=1
      # C1(3000) -> C2(6000)   depth: C1=2, C2=1
      #
      # Layer-based scheduler groups nodes by dependency levels:
      # - Layer 1: [c1, b1, a1] (all roots, sorted by depth asc then timestamp desc)
      # - Layer 2: [c2, b2, a2] (all outputs, sorted by depth asc then timestamp desc)
      #
      # This enables parallel execution within each layer.
      nodes = %{
        "node_1000_a1" => %{},
        "node_4000_a2" => %{},
        "node_2000_b1" => %{},
        "node_5000_b2" => %{},
        "node_3000_c1" => %{},
        "node_6000_c2" => %{}
      }

      edges = [
        %{"source" => "node_1000_a1", "target" => "node_4000_a2"},
        %{"source" => "node_2000_b1", "target" => "node_5000_b2"},
        %{"source" => "node_3000_c1", "target" => "node_6000_c2"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # All 6 nodes present
      assert length(sorted) == 6

      # Verify topological constraints for each chain
      assert Enum.find_index(sorted, &(&1 == "node_1000_a1")) <
               Enum.find_index(sorted, &(&1 == "node_4000_a2"))

      assert Enum.find_index(sorted, &(&1 == "node_2000_b1")) <
               Enum.find_index(sorted, &(&1 == "node_5000_b2"))

      assert Enum.find_index(sorted, &(&1 == "node_3000_c1")) <
               Enum.find_index(sorted, &(&1 == "node_6000_c2"))

      # Layer 1: All roots (depth 2), sorted by timestamp desc: c1(3000), b1(2000), a1(1000)
      assert hd(sorted) == "node_3000_c1"
      assert Enum.at(sorted, 1) == "node_2000_b1"
      assert Enum.at(sorted, 2) == "node_1000_a1"

      # Layer 2: All outputs (depth 1), sorted by timestamp desc: c2(6000), b2(5000), a2(4000)
      assert Enum.at(sorted, 3) == "node_6000_c2"
      assert Enum.at(sorted, 4) == "node_5000_b2"
      assert Enum.at(sorted, 5) == "node_4000_a2"
    end

    test "handles nodes with underscore-heavy IDs" do
      # Test that timestamp extraction handles complex ID formats
      nodes = %{
        "node_1000_foo_bar_baz" => %{},
        "node_2000_test" => %{},
        "some_other_format" => %{},
        "no_timestamp" => %{}
      }

      edges = []

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      assert length(sorted) == 4
      # node_2000_test (ts=2000) first, then node_1000 (ts=1000), then others (ts=0)
      assert hd(sorted) == "node_2000_test"
      assert Enum.at(sorted, 1) == "node_1000_foo_bar_baz"
    end

    test "handles duplicate edges gracefully" do
      # Same edge specified twice should not break anything
      nodes = %{
        "node_1000_a" => %{},
        "node_2000_b" => %{}
      }

      edges = [
        %{"source" => "node_1000_a", "target" => "node_2000_b"},
        %{"source" => "node_1000_a", "target" => "node_2000_b"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # Should still produce valid topological order
      assert sorted == ["node_1000_a", "node_2000_b"]
    end

    test "handles very wide graph (many roots)" do
      # 20 independent nodes (all roots, all outputs)
      nodes =
        1..20
        |> Enum.map(fn i -> {"node_#{i * 100}_n#{i}", %{}} end)
        |> Map.new()

      edges = []

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # All 20 nodes should be present, sorted by timestamp descending
      assert length(sorted) == 20

      # Verify descending timestamp order (all depth 1)
      timestamps =
        Enum.map(sorted, fn id ->
          [_, ts | _] = String.split(id, "_")
          String.to_integer(ts)
        end)

      assert timestamps == Enum.sort(timestamps, :desc)
    end

    test "complex cycle detection: cycle reachable from acyclic path" do
      # A -> B -> C -> D -> B (cycle)
      #      ^
      # Where A is not part of the cycle but leads into it
      nodes = %{
        "node_1000_a" => %{},
        "node_2000_b" => %{},
        "node_3000_c" => %{},
        "node_4000_d" => %{}
      }

      edges = [
        %{"source" => "node_1000_a", "target" => "node_2000_b"},
        %{"source" => "node_2000_b", "target" => "node_3000_c"},
        %{"source" => "node_3000_c", "target" => "node_4000_d"},
        %{"source" => "node_4000_d", "target" => "node_2000_b"}
      ]

      # Should detect cycle even though A is not in the cycle
      assert {:error, :cycle_detected, %{}} = Scheduler.schedule_flat(nodes, edges)
    end

    test "handles mixed workflow with preview at multiple depths" do
      # Real-world scenario: Multiple preview nodes at different pipeline stages
      # Load -> Gen1 -> Preview1
      #      -> Gen2 -> Preview2
      #              -> Upscale -> Preview3
      #                        -> SaveImage
      nodes = %{
        "node_1000_load" => %{},
        "node_2000_gen1" => %{},
        "node_3000_prev1" => %{},
        "node_4000_gen2" => %{},
        "node_5000_prev2" => %{},
        "node_6000_upscale" => %{},
        "node_7000_prev3" => %{},
        "node_8000_save" => %{}
      }

      edges = [
        %{"source" => "node_1000_load", "target" => "node_2000_gen1"},
        %{"source" => "node_2000_gen1", "target" => "node_3000_prev1"},
        %{"source" => "node_1000_load", "target" => "node_4000_gen2"},
        %{"source" => "node_4000_gen2", "target" => "node_5000_prev2"},
        %{"source" => "node_4000_gen2", "target" => "node_6000_upscale"},
        %{"source" => "node_6000_upscale", "target" => "node_7000_prev3"},
        %{"source" => "node_6000_upscale", "target" => "node_8000_save"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # load must be first
      assert hd(sorted) == "node_1000_load"

      # All nodes present
      assert length(sorted) == 8

      # Verify all topological constraints
      load_idx = Enum.find_index(sorted, &(&1 == "node_1000_load"))
      gen1_idx = Enum.find_index(sorted, &(&1 == "node_2000_gen1"))
      prev1_idx = Enum.find_index(sorted, &(&1 == "node_3000_prev1"))
      gen2_idx = Enum.find_index(sorted, &(&1 == "node_4000_gen2"))
      prev2_idx = Enum.find_index(sorted, &(&1 == "node_5000_prev2"))
      upscale_idx = Enum.find_index(sorted, &(&1 == "node_6000_upscale"))
      prev3_idx = Enum.find_index(sorted, &(&1 == "node_7000_prev3"))
      save_idx = Enum.find_index(sorted, &(&1 == "node_8000_save"))

      assert load_idx < gen1_idx
      assert gen1_idx < prev1_idx
      assert load_idx < gen2_idx
      assert gen2_idx < prev2_idx
      assert gen2_idx < upscale_idx
      assert upscale_idx < prev3_idx
      assert upscale_idx < save_idx
    end
  end

  describe "created_at timestamp ordering" do
    test "uses data.created_at for ordering when available" do
      # Three independent nodes with explicit created_at timestamps
      # Node with highest created_at should execute first (timestamp DESC)
      nodes = %{
        "node_a" => %{"data" => %{"created_at" => 1000}},
        "node_b" => %{"data" => %{"created_at" => 3000}},
        "node_c" => %{"data" => %{"created_at" => 2000}}
      }

      edges = []

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # All depth 1, sorted by created_at descending: b(3000), c(2000), a(1000)
      assert sorted == ["node_b", "node_c", "node_a"]
    end

    test "falls back to ID parsing when created_at not available" do
      # Mix of nodes: some with created_at, some without
      nodes = %{
        "node_1000_legacy" => %{},
        "node_2000_legacy" => %{},
        "node_new" => %{"data" => %{"created_at" => 1500}}
      }

      edges = []

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # legacy2 (ts=2000), new (ts=1500), legacy1 (ts=1000)
      assert sorted == ["node_2000_legacy", "node_new", "node_1000_legacy"]
    end

    test "handles non-standard IDs with created_at" do
      # Nodes with IDs that don't follow the node_timestamp_random format
      # These would get timestamp 0 with ID parsing, but have explicit created_at
      nodes = %{
        "custom_id_1" => %{"data" => %{"created_at" => 2000}},
        "my_special_node" => %{"data" => %{"created_at" => 3000}},
        "another_one" => %{"data" => %{"created_at" => 1000}}
      }

      edges = []

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # Sorted by created_at descending
      assert sorted == ["my_special_node", "custom_id_1", "another_one"]
    end

    test "handles mixed ID formats with and without created_at" do
      # Real-world scenario: LLM-generated nodes (no timestamp in ID)
      # mixed with user-created nodes (timestamp in ID)
      nodes = %{
        # LLM-generated with explicit created_at
        "llm_node_1" => %{"data" => %{"created_at" => 2500}},
        # User-created with legacy ID format (no explicit created_at)
        "node_3000_user" => %{},
        # LLM-generated without created_at (edge case - gets timestamp 0)
        "llm_node_2" => %{}
      }

      edges = []

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # user (3000 from ID), llm_1 (2500 from created_at), llm_2 (0 fallback)
      assert sorted == ["node_3000_user", "llm_node_1", "llm_node_2"]
    end

    test "created_at in workflow with edges respects topological order" do
      # A -> B -> C
      # B has highest created_at but must still execute after A
      nodes = %{
        "node_a" => %{"data" => %{"created_at" => 1000}},
        "node_b" => %{"data" => %{"created_at" => 3000}},
        "node_c" => %{"data" => %{"created_at" => 2000}}
      }

      edges = [
        %{"source" => "node_a", "target" => "node_b"},
        %{"source" => "node_b", "target" => "node_c"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # Topological constraint overrides timestamp
      assert sorted == ["node_a", "node_b", "node_c"]
    end

    test "created_at tiebreaker within same depth" do
      # Diamond pattern where B and C have same depth
      #     A
      #    / \
      #   B   C
      #    \ /
      #     D
      nodes = %{
        "node_a" => %{"data" => %{"created_at" => 1000}},
        "node_b" => %{"data" => %{"created_at" => 2000}},
        "node_c" => %{"data" => %{"created_at" => 3000}},
        "node_d" => %{"data" => %{"created_at" => 4000}}
      }

      edges = [
        %{"source" => "node_a", "target" => "node_b"},
        %{"source" => "node_a", "target" => "node_c"},
        %{"source" => "node_b", "target" => "node_d"},
        %{"source" => "node_c", "target" => "node_d"}
      ]

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # A first (only root), D last (depends on both)
      assert hd(sorted) == "node_a"
      assert List.last(sorted) == "node_d"

      # B and C both depth 2, C has higher created_at so executes first
      assert Enum.at(sorted, 1) == "node_c"
      assert Enum.at(sorted, 2) == "node_b"
    end

    test "handles top-level created_at field" do
      # Some systems might put created_at at top level instead of in data
      nodes = %{
        "node_a" => %{"created_at" => 1000},
        "node_b" => %{"created_at" => 3000},
        "node_c" => %{"created_at" => 2000}
      }

      edges = []

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      assert sorted == ["node_b", "node_c", "node_a"]
    end

    test "data.created_at takes precedence over top-level created_at" do
      # Edge case: both locations have created_at
      nodes = %{
        "node_a" => %{"created_at" => 9999, "data" => %{"created_at" => 1000}},
        "node_b" => %{"created_at" => 1, "data" => %{"created_at" => 2000}}
      }

      edges = []

      {:ok, sorted} = Scheduler.schedule_flat(nodes, edges)

      # data.created_at is preferred: b(2000), a(1000)
      assert sorted == ["node_b", "node_a"]
    end
  end
end
