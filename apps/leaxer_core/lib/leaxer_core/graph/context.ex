defmodule LeaxerCore.Graph.Context do
  @moduledoc """
  Manages execution context - stores intermediate tensors between node executions.

  ## Memory Management

  The context tracks how many downstream nodes consume each output. When the last
  consumer reads an output, it is automatically garbage collected to prevent memory
  leaks in large workflows. This is implemented via the `consumer_counts` field and
  the `consume_input/2` function.
  """

  defstruct [:job_id, :outputs, :current_node, :started_at, :consumer_counts]

  @type t :: %__MODULE__{
          job_id: String.t(),
          outputs: %{String.t() => map()},
          current_node: String.t() | nil,
          started_at: DateTime.t(),
          consumer_counts: %{String.t() => non_neg_integer()}
        }

  @doc """
  Create a new context with optional edge information for consumer counting.

  When edges are provided, the context tracks how many nodes consume each output,
  enabling automatic garbage collection when outputs are no longer needed.
  """
  def new(job_id, edges \\ []) do
    # Build consumer counts from edges - count how many nodes consume each source
    consumer_counts =
      edges
      |> Enum.group_by(fn edge -> edge["source"] end)
      |> Enum.map(fn {source, edges_from_source} -> {source, length(edges_from_source)} end)
      |> Map.new()

    %__MODULE__{
      job_id: job_id,
      outputs: %{},
      current_node: nil,
      started_at: DateTime.utc_now(),
      consumer_counts: consumer_counts
    }
  end

  def put_output(ctx, node_id, output) do
    %{ctx | outputs: Map.put(ctx.outputs, node_id, output)}
  end

  def get_output(ctx, node_id) do
    Map.get(ctx.outputs, node_id)
  end

  def set_current_node(ctx, node_id) do
    %{ctx | current_node: node_id}
  end

  @doc """
  Mark an input as consumed and garbage collect the output if this was the last consumer.

  Call this after gathering each input to enable memory cleanup for large workflows.
  When the last consumer reads an output, the output data is deleted from the context.
  """
  @spec consume_input(t(), String.t()) :: t()
  def consume_input(ctx, source_node_id) do
    case Map.get(ctx.consumer_counts, source_node_id) do
      # Last consumer - delete the output to free memory
      1 ->
        %{
          ctx
          | outputs: Map.delete(ctx.outputs, source_node_id),
            consumer_counts: Map.delete(ctx.consumer_counts, source_node_id)
        }

      # More consumers remaining - decrement the count
      n when is_integer(n) and n > 1 ->
        %{ctx | consumer_counts: Map.put(ctx.consumer_counts, source_node_id, n - 1)}

      # No consumer tracking for this node (edges not provided) - do nothing
      nil ->
        ctx
    end
  end
end
