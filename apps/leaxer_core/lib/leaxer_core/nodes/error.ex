defmodule LeaxerCore.Nodes.Error do
  @moduledoc """
  Structured error representation for node execution.

  Provides consistent error formatting and metadata for debugging
  and observability across the node system.
  """

  @type t :: %__MODULE__{
          code: atom(),
          message: String.t(),
          node_id: String.t() | nil,
          node_type: String.t() | nil,
          field: String.t() | nil,
          correlation_id: String.t() | nil,
          details: map()
        }

  defstruct [
    :code,
    :message,
    :node_id,
    :node_type,
    :field,
    :correlation_id,
    details: %{}
  ]

  @doc """
  Creates a new error with the given code and message.

  ## Examples

      iex> Error.new(:validation_failed, "Input 'a' must be a number")
      %Error{code: :validation_failed, message: "Input 'a' must be a number"}
  """
  @spec new(atom(), String.t(), keyword()) :: t()
  def new(code, message, opts \\ []) do
    %__MODULE__{
      code: code,
      message: message,
      node_id: Keyword.get(opts, :node_id),
      node_type: Keyword.get(opts, :node_type),
      field: Keyword.get(opts, :field),
      correlation_id: Keyword.get(opts, :correlation_id) || generate_correlation_id(),
      details: Keyword.get(opts, :details, %{})
    }
  end

  @doc """
  Creates a validation error for a specific field.
  """
  @spec validation_error(String.t(), String.t(), keyword()) :: t()
  def validation_error(field, message, opts \\ []) do
    new(:validation_failed, message, Keyword.merge(opts, field: field))
  end

  @doc """
  Creates a type mismatch error.
  """
  @spec type_error(String.t(), String.t(), String.t(), keyword()) :: t()
  def type_error(field, expected, got, opts \\ []) do
    message = "Field '#{field}' expected type #{expected}, got #{got}"

    new(
      :type_mismatch,
      message,
      Keyword.merge(opts, field: field, details: %{expected: expected, got: got})
    )
  end

  @doc """
  Creates a range error for numeric values.
  """
  @spec range_error(String.t(), number(), number() | nil, number() | nil, keyword()) :: t()
  def range_error(field, value, min, max, opts \\ []) do
    message =
      cond do
        min != nil && max != nil ->
          "Field '#{field}' value #{value} must be between #{min} and #{max}"

        min != nil ->
          "Field '#{field}' value #{value} must be at least #{min}"

        max != nil ->
          "Field '#{field}' value #{value} must be at most #{max}"

        true ->
          "Field '#{field}' value #{value} is out of range"
      end

    details = %{value: value}
    details = if min, do: Map.put(details, :min, min), else: details
    details = if max, do: Map.put(details, :max, max), else: details

    new(:out_of_range, message, Keyword.merge(opts, field: field, details: details))
  end

  @doc """
  Creates an invalid enum value error.
  """
  @spec enum_error(String.t(), any(), [String.t()], keyword()) :: t()
  def enum_error(field, value, valid_options, opts \\ []) do
    options_str = Enum.join(valid_options, ", ")
    message = "Field '#{field}' value '#{inspect(value)}' is not one of: #{options_str}"

    new(
      :invalid_enum,
      message,
      Keyword.merge(opts, field: field, details: %{value: value, valid_options: valid_options})
    )
  end

  @doc """
  Creates a regex compilation error.
  """
  @spec regex_error(String.t(), String.t(), keyword()) :: t()
  def regex_error(pattern, reason, opts \\ []) do
    message = "Invalid regex pattern '#{pattern}': #{reason}"

    new(
      :invalid_regex,
      message,
      Keyword.merge(opts, details: %{pattern: pattern, reason: reason})
    )
  end

  @doc """
  Creates a required field missing error.
  """
  @spec required_error(String.t(), keyword()) :: t()
  def required_error(field, opts \\ []) do
    message = "Field '#{field}' is required"
    new(:required_field, message, Keyword.merge(opts, field: field))
  end

  @doc """
  Creates an execution error.
  """
  @spec execution_error(String.t(), keyword()) :: t()
  def execution_error(message, opts \\ []) do
    new(:execution_failed, message, opts)
  end

  @doc """
  Converts the error to a map for JSON serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = error) do
    %{
      code: error.code,
      message: error.message,
      node_id: error.node_id,
      node_type: error.node_type,
      field: error.field,
      correlation_id: error.correlation_id,
      details: error.details
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Converts the error to a tuple format for process returns.
  """
  @spec to_tuple(t()) :: {:error, map()}
  def to_tuple(%__MODULE__{} = error) do
    {:error, to_map(error)}
  end

  @doc """
  Wraps an error result with node context.
  """
  @spec with_context(t(), String.t(), String.t()) :: t()
  def with_context(%__MODULE__{} = error, node_id, node_type) do
    %{error | node_id: error.node_id || node_id, node_type: error.node_type || node_type}
  end

  # Private helpers

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
  end
end
