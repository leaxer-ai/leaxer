defmodule LeaxerCore.Nodes do
  @moduledoc """
  Public API for the node registry.

  This module provides a simple interface for looking up node modules
  and retrieving node metadata. It delegates to `LeaxerCore.Nodes.Registry`
  for the actual implementation.

  ## Examples

      # Get a node module
      LeaxerCore.Nodes.get_module("MathOp")
      #=> LeaxerCore.Nodes.Math.MathOp

      # List all node types
      LeaxerCore.Nodes.list_types()
      #=> ["Abs", "And", "BigInt", ...]

      # Get all nodes with metadata (for API)
      LeaxerCore.Nodes.list_all_with_metadata()
      #=> [%{type: "Abs", label: "Absolute", category: "Math", ...}, ...]
  """

  @doc """
  Gets the module for a given node type.
  Returns nil if the type is not registered.
  """
  defdelegate get_module(type), to: LeaxerCore.Nodes.Registry

  @doc """
  Lists all registered node type strings.
  """
  defdelegate list_types(), to: LeaxerCore.Nodes.Registry

  @doc """
  Lists all registered nodes with their full metadata.
  This is the main API used by the frontend.
  """
  defdelegate list_all_with_metadata(), to: LeaxerCore.Nodes.Registry

  @doc """
  Gets metadata for a specific node type.
  Returns `{:ok, metadata}` or `{:error, :not_found}`.
  """
  defdelegate get_metadata(type), to: LeaxerCore.Nodes.Registry

  @doc """
  Reloads custom nodes from the custom_nodes directory.
  """
  defdelegate reload_custom_nodes(), to: LeaxerCore.Nodes.Registry

  @doc """
  Returns statistics about registered nodes.
  """
  defdelegate stats(), to: LeaxerCore.Nodes.Registry
end
