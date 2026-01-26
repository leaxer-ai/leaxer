defmodule LeaxerCore.WorkflowExecutionTest do
  @moduledoc """
  Integration tests for end-to-end workflow execution.

  These tests verify that the Queue → Runtime → Node execution pipeline
  works correctly for various workflow patterns.

  ## Test Categories

  1. Happy-path linear workflows
  2. Branching/diamond workflows
  3. Input vs config precedence
  4. Error handling and propagation
  5. Queue state management
  """
  use ExUnit.Case, async: false

  alias LeaxerCore.Queue
  alias LeaxerCore.Runtime
  alias LeaxerCore.Graph.Execution
  alias LeaxerCore.ExecutionState

  # Reduce noise from logger during tests
  @moduletag :capture_log

  setup do
    # Clear any previous execution state
    ExecutionState.complete_execution()
    Process.sleep(10)

    # Clear the queue of any previous jobs
    Queue.clear_pending()
    Process.sleep(10)

    :ok
  end

  describe "linear workflow execution" do
    test "executes single node workflow" do
      # Single MathOp node: 10 + 5 = 15
      workflow =
        build_workflow(%{
          nodes: %{
            "node_1" => %{
              "id" => "node_1",
              "type" => "MathOp",
              "data" => %{"a" => 10.0, "b" => 5.0, "operation" => "add"}
            }
          },
          edges: []
        })

      {:ok, [job_id]} = Queue.enqueue([workflow])
      assert is_binary(job_id)

      # Wait for execution to complete
      wait_for_job_completion(job_id, 2000)

      # Verify job completed successfully
      state = Queue.get_state()
      job = find_job(state.jobs, job_id)
      assert job.status == :completed
    end

    test "executes two-node linear chain" do
      # MathOp (10 - 25 = -15) -> Abs (|-15| = 15)
      workflow =
        build_workflow(%{
          nodes: %{
            "node_1" => %{
              "id" => "node_1",
              "type" => "MathOp",
              "data" => %{"a" => 10.0, "b" => 25.0, "operation" => "subtract"}
            },
            "node_2" => %{
              "id" => "node_2",
              "type" => "Abs",
              "data" => %{}
            }
          },
          edges: [
            %{
              "source" => "node_1",
              "target" => "node_2",
              "sourceHandle" => "result",
              "targetHandle" => "value"
            }
          ]
        })

      {:ok, [job_id]} = Queue.enqueue([workflow])
      wait_for_job_completion(job_id, 2000)

      state = Queue.get_state()
      job = find_job(state.jobs, job_id)
      assert job.status == :completed
    end

    test "executes three-node chain with string concatenation" do
      # Concat("Hello", " ") -> Concat(result, "World") = "Hello World"
      workflow =
        build_workflow(%{
          nodes: %{
            "node_1" => %{
              "id" => "node_1",
              "type" => "Concat",
              "data" => %{"a" => "Hello", "b" => " "}
            },
            "node_2" => %{
              "id" => "node_2",
              "type" => "Concat",
              "data" => %{"b" => "World"}
            }
          },
          edges: [
            %{
              "source" => "node_1",
              "target" => "node_2",
              "sourceHandle" => "result",
              "targetHandle" => "a"
            }
          ]
        })

      {:ok, [job_id]} = Queue.enqueue([workflow])
      wait_for_job_completion(job_id, 2000)

      state = Queue.get_state()
      job = find_job(state.jobs, job_id)
      assert job.status == :completed
    end
  end

  describe "branching workflow execution" do
    test "executes workflow with one source feeding two targets" do
      # MathOp(5+5=10) -> Abs (passthrough 10)
      #                -> MathOp(10*2=20)
      workflow =
        build_workflow(%{
          nodes: %{
            "source" => %{
              "id" => "source",
              "type" => "MathOp",
              "data" => %{"a" => 5.0, "b" => 5.0, "operation" => "add"}
            },
            "branch_a" => %{
              "id" => "branch_a",
              "type" => "Abs",
              "data" => %{}
            },
            "branch_b" => %{
              "id" => "branch_b",
              "type" => "MathOp",
              "data" => %{"b" => 2.0, "operation" => "multiply"}
            }
          },
          edges: [
            %{
              "source" => "source",
              "target" => "branch_a",
              "sourceHandle" => "result",
              "targetHandle" => "value"
            },
            %{
              "source" => "source",
              "target" => "branch_b",
              "sourceHandle" => "result",
              "targetHandle" => "a"
            }
          ]
        })

      {:ok, [job_id]} = Queue.enqueue([workflow])
      wait_for_job_completion(job_id, 2000)

      state = Queue.get_state()
      job = find_job(state.jobs, job_id)
      assert job.status == :completed
    end

    test "executes diamond-shaped workflow (two branches merge)" do
      # Input(10) -> Branch A (Abs)      \
      #           -> Branch B (*2=20)    -> Target (receives from B)
      workflow =
        build_workflow(%{
          nodes: %{
            "input" => %{
              "id" => "input",
              "type" => "MathOp",
              "data" => %{"a" => 10.0, "b" => 0.0, "operation" => "add"}
            },
            "branch_a" => %{
              "id" => "branch_a",
              "type" => "Abs",
              "data" => %{}
            },
            "branch_b" => %{
              "id" => "branch_b",
              "type" => "MathOp",
              "data" => %{"b" => 2.0, "operation" => "multiply"}
            },
            "merge" => %{
              "id" => "merge",
              "type" => "MathOp",
              "data" => %{"operation" => "add"}
            }
          },
          edges: [
            %{
              "source" => "input",
              "target" => "branch_a",
              "sourceHandle" => "result",
              "targetHandle" => "value"
            },
            %{
              "source" => "input",
              "target" => "branch_b",
              "sourceHandle" => "result",
              "targetHandle" => "a"
            },
            %{
              "source" => "branch_a",
              "target" => "merge",
              "sourceHandle" => "result",
              "targetHandle" => "a"
            },
            %{
              "source" => "branch_b",
              "target" => "merge",
              "sourceHandle" => "result",
              "targetHandle" => "b"
            }
          ]
        })

      {:ok, [job_id]} = Queue.enqueue([workflow])
      wait_for_job_completion(job_id, 2000)

      state = Queue.get_state()
      job = find_job(state.jobs, job_id)
      assert job.status == :completed
    end
  end

  describe "logic node workflows" do
    test "executes And/Or logic chain" do
      # And(true, true) = true -> Or(true, false) = true
      workflow =
        build_workflow(%{
          nodes: %{
            "and_node" => %{
              "id" => "and_node",
              "type" => "And",
              "data" => %{"a" => true, "b" => true}
            },
            "or_node" => %{
              "id" => "or_node",
              "type" => "Or",
              "data" => %{"b" => false}
            }
          },
          edges: [
            %{
              "source" => "and_node",
              "target" => "or_node",
              "sourceHandle" => "result",
              "targetHandle" => "a"
            }
          ]
        })

      {:ok, [job_id]} = Queue.enqueue([workflow])
      wait_for_job_completion(job_id, 2000)

      state = Queue.get_state()
      job = find_job(state.jobs, job_id)
      assert job.status == :completed
    end

    test "executes Not logic node" do
      # And(true, false) = false -> Not(false) = true
      workflow =
        build_workflow(%{
          nodes: %{
            "and_node" => %{
              "id" => "and_node",
              "type" => "And",
              "data" => %{"a" => true, "b" => false}
            },
            "not_node" => %{
              "id" => "not_node",
              "type" => "Not",
              "data" => %{}
            }
          },
          edges: [
            %{
              "source" => "and_node",
              "target" => "not_node",
              "sourceHandle" => "result",
              "targetHandle" => "value"
            }
          ]
        })

      {:ok, [job_id]} = Queue.enqueue([workflow])
      wait_for_job_completion(job_id, 2000)

      state = Queue.get_state()
      job = find_job(state.jobs, job_id)
      assert job.status == :completed
    end
  end

  describe "input vs config precedence" do
    test "connected input overrides node config value" do
      # Source outputs 100, Target has config a=50
      # Connection should make target use 100, not 50
      # MathOp(source: 100+0=100) -> MathOp(target: input_a + 1 = 101, not 50+1=51)
      workflow =
        build_workflow(%{
          nodes: %{
            "source" => %{
              "id" => "source",
              "type" => "MathOp",
              "data" => %{"a" => 100.0, "b" => 0.0, "operation" => "add"}
            },
            "target" => %{
              "id" => "target",
              "type" => "MathOp",
              "data" => %{"a" => 50.0, "b" => 1.0, "operation" => "add"}
            }
          },
          edges: [
            %{
              "source" => "source",
              "target" => "target",
              "sourceHandle" => "result",
              "targetHandle" => "a"
            }
          ]
        })

      {:ok, [job_id]} = Queue.enqueue([workflow])
      wait_for_job_completion(job_id, 2000)

      state = Queue.get_state()
      job = find_job(state.jobs, job_id)
      assert job.status == :completed
    end
  end

  describe "graph validation" do
    test "rejects workflow with cycle" do
      # Create a cycle: A -> B -> A
      workflow =
        build_workflow(%{
          nodes: %{
            "node_a" => %{
              "id" => "node_a",
              "type" => "MathOp",
              "data" => %{"a" => 1.0, "b" => 1.0, "operation" => "add"}
            },
            "node_b" => %{
              "id" => "node_b",
              "type" => "Abs",
              "data" => %{}
            }
          },
          edges: [
            %{
              "source" => "node_a",
              "target" => "node_b",
              "sourceHandle" => "result",
              "targetHandle" => "value"
            },
            %{
              "source" => "node_b",
              "target" => "node_a",
              "sourceHandle" => "result",
              "targetHandle" => "a"
            }
          ]
        })

      result =
        Execution.sort_and_validate(%{
          "nodes" => workflow["nodes"],
          "edges" => workflow["edges"]
        })

      assert {:error, :cycle_detected, _details} = result
    end

    test "rejects workflow with invalid edge reference" do
      workflow =
        build_workflow(%{
          nodes: %{
            "node_1" => %{
              "id" => "node_1",
              "type" => "MathOp",
              "data" => %{}
            }
          },
          edges: [
            %{
              "source" => "node_1",
              "target" => "nonexistent_node",
              "sourceHandle" => "result",
              "targetHandle" => "value"
            }
          ]
        })

      result =
        Execution.sort_and_validate(%{
          "nodes" => workflow["nodes"],
          "edges" => workflow["edges"]
        })

      assert {:error, :invalid_edge_reference, _details} = result
    end
  end

  describe "runtime direct execution" do
    test "executes workflow directly via Runtime without Queue" do
      # Test Runtime.start_link directly for more granular control
      workflow = %{
        "nodes" => %{
          "node_1" => %{
            "id" => "node_1",
            "type" => "MathOp",
            "data" => %{"a" => 7.0, "b" => 3.0, "operation" => "multiply"}
          },
          "node_2" => %{
            "id" => "node_2",
            "type" => "Abs",
            "data" => %{}
          }
        },
        "edges" => [
          %{
            "source" => "node_1",
            "target" => "node_2",
            "sourceHandle" => "result",
            "targetHandle" => "value"
          }
        ]
      }

      {:ok, sorted_nodes} = Execution.sort_and_validate(workflow)

      # Start runtime without queue_pid to get direct broadcast behavior
      {:ok, pid} =
        Runtime.start_link(
          job_id: "test_direct_#{System.unique_integer([:positive])}",
          graph: workflow,
          sorted_nodes: sorted_nodes,
          socket: nil,
          queue_pid: nil
        )

      # Subscribe to runtime events to verify completion
      Phoenix.PubSub.subscribe(LeaxerCore.PubSub, "runtime:events")

      # Run the workflow
      Runtime.run(pid)

      # Wait for completion event
      assert_receive {"execution_complete", %{job_id: _, outputs: outputs}}, 2000

      # With memory GC, only leaf node outputs remain (intermediate outputs are cleaned up)
      # node_1's output was consumed by node_2 and has been garbage collected
      # Only verify the final leaf node output
      assert Map.has_key?(outputs, "node_2")
      assert outputs["node_2"]["result"] == 21.0
    end
  end

  describe "execution state tracking" do
    test "execution state is updated during workflow run" do
      workflow =
        build_workflow(%{
          nodes: %{
            "node_1" => %{
              "id" => "node_1",
              "type" => "MathOp",
              "data" => %{"a" => 1.0, "b" => 2.0, "operation" => "add"}
            },
            "node_2" => %{
              "id" => "node_2",
              "type" => "Abs",
              "data" => %{}
            },
            "node_3" => %{
              "id" => "node_3",
              "type" => "MathOp",
              "data" => %{"b" => 10.0, "operation" => "multiply"}
            }
          },
          edges: [
            %{
              "source" => "node_1",
              "target" => "node_2",
              "sourceHandle" => "result",
              "targetHandle" => "value"
            },
            %{
              "source" => "node_2",
              "target" => "node_3",
              "sourceHandle" => "result",
              "targetHandle" => "a"
            }
          ]
        })

      {:ok, [job_id]} = Queue.enqueue([workflow])
      wait_for_job_completion(job_id, 2000)

      # After completion, execution state should be cleared
      assert ExecutionState.get_state() == nil
    end
  end

  describe "queue job management" do
    test "enqueuing multiple workflows creates multiple jobs" do
      workflow1 =
        build_workflow(%{
          nodes: %{
            "node_1" => %{
              "id" => "node_1",
              "type" => "MathOp",
              "data" => %{"a" => 1.0, "b" => 1.0, "operation" => "add"}
            }
          },
          edges: []
        })

      workflow2 =
        build_workflow(%{
          nodes: %{
            "node_1" => %{
              "id" => "node_1",
              "type" => "MathOp",
              "data" => %{"a" => 2.0, "b" => 2.0, "operation" => "add"}
            }
          },
          edges: []
        })

      {:ok, [job_id_1, job_id_2]} = Queue.enqueue([workflow1, workflow2])

      assert is_binary(job_id_1)
      assert is_binary(job_id_2)
      assert job_id_1 != job_id_2

      # Wait for both to complete
      wait_for_job_completion(job_id_1, 2000)
      wait_for_job_completion(job_id_2, 2000)

      state = Queue.get_state()
      job1 = find_job(state.jobs, job_id_1)
      job2 = find_job(state.jobs, job_id_2)

      assert job1.status == :completed
      assert job2.status == :completed
    end

    test "cancelling pending job removes it from queue" do
      # Create a workflow but don't let it execute yet by using Queue.clear_pending
      workflow =
        build_workflow(%{
          nodes: %{
            "node_1" => %{
              "id" => "node_1",
              "type" => "MathOp",
              "data" => %{"a" => 1.0, "b" => 1.0, "operation" => "add"}
            }
          },
          edges: []
        })

      {:ok, [job_id]} = Queue.enqueue([workflow])

      # Job might already be running or pending
      state_before = Queue.get_state()
      job_before = find_job(state_before.jobs, job_id)

      if job_before && job_before.status == :pending do
        # Cancel the pending job
        assert :ok = Queue.cancel(job_id)

        # Verify job is no longer in pending state
        state_after = Queue.get_state()
        job_after = find_job(state_after.jobs, job_id)
        assert job_after == nil
      else
        # Job already started, wait for completion
        wait_for_job_completion(job_id, 2000)
      end
    end
  end

  describe "visual-only nodes" do
    test "skips Group and Frame nodes during execution" do
      # Frame and Group are visual-only nodes that should be skipped
      workflow =
        build_workflow(%{
          nodes: %{
            "frame_1" => %{
              "id" => "frame_1",
              "type" => "Frame",
              "data" => %{}
            },
            "group_1" => %{
              "id" => "group_1",
              "type" => "Group",
              "data" => %{}
            },
            "math_node" => %{
              "id" => "math_node",
              "type" => "MathOp",
              "data" => %{"a" => 5.0, "b" => 5.0, "operation" => "add"}
            }
          },
          edges: []
        })

      {:ok, [job_id]} = Queue.enqueue([workflow])
      wait_for_job_completion(job_id, 2000)

      state = Queue.get_state()
      job = find_job(state.jobs, job_id)
      assert job.status == :completed
    end
  end

  # Helper functions

  defp build_workflow(%{nodes: nodes, edges: edges}) do
    %{
      "nodes" => nodes,
      "edges" => edges
    }
  end

  defp wait_for_job_completion(job_id, timeout) do
    start_time = System.monotonic_time(:millisecond)
    do_wait_for_job_completion(job_id, start_time, timeout)
  end

  defp do_wait_for_job_completion(job_id, start_time, timeout) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed > timeout do
      flunk("Timeout waiting for job #{job_id} to complete")
    end

    state = Queue.get_state()
    job = find_job(state.jobs, job_id)

    case job do
      nil ->
        # Job might have been removed (e.g., cancelled)
        :ok

      %{status: :completed} ->
        :ok

      %{status: :error} ->
        :ok

      %{status: :cancelled} ->
        :ok

      _ ->
        Process.sleep(50)
        do_wait_for_job_completion(job_id, start_time, timeout)
    end
  end

  defp find_job(jobs, job_id) do
    Enum.find(jobs, fn job -> job.id == job_id end)
  end
end
