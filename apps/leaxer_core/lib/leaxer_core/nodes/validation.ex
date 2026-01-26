defmodule LeaxerCore.Nodes.Validation do
  @moduledoc """
  Input validation for node execution.

  Validates inputs against the node's input specification before execution,
  ensuring type correctness, range constraints, and enum validity.
  """

  alias LeaxerCore.Nodes.Error
  alias LeaxerCore.Nodes.Behaviour
  alias LeaxerCore.Nodes.Types

  @doc """
  Validates all inputs against the input specification.

  Returns `:ok` if all validations pass, or `{:error, Error.t()}` with the first error.

  ## Parameters
  - `inputs` - Map of input values from connections
  - `config` - Map of config values from UI widgets
  - `input_spec` - The node's input specification

  ## Examples

      iex> Validation.validate_inputs(%{"a" => 5}, %{}, %{a: %{type: :integer, label: "A"}})
      :ok

      iex> Validation.validate_inputs(%{}, %{"a" => "not a number"}, %{a: %{type: :integer, label: "A", min: 0}})
      {:error, %Error{code: :type_mismatch, ...}}
  """
  @spec validate_inputs(map(), map(), map()) :: :ok | {:error, Error.t()}
  def validate_inputs(inputs, config, input_spec) do
    normalized_spec = Behaviour.normalize_input_spec(input_spec)

    # Merge inputs and config, inputs take precedence
    merged = Map.merge(config, inputs)

    # Validate each field in the spec
    Enum.reduce_while(normalized_spec, :ok, fn {key, field_spec}, :ok ->
      key_str = to_string(key)
      value = Map.get(merged, key_str)

      case validate_field(key_str, value, field_spec) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @doc """
  Validates a single field value against its specification.
  """
  @spec validate_field(String.t(), any(), map()) :: :ok | {:error, Error.t()}
  def validate_field(key, value, field_spec) do
    # field_spec is guaranteed to have atom keys from normalize_input_spec
    type = field_spec[:type]
    type_str = normalize_type_string(type)

    # Skip validation if value is nil and field is optional, has a default, or is data-only
    is_optional = field_spec[:optional] == true
    has_default = Map.has_key?(field_spec, :default)

    if is_nil(value) do
      cond do
        # Explicitly optional fields are OK nil
        is_optional -> :ok
        # Fields with defaults are OK nil
        has_default -> :ok
        # Data types (model, image, controlnet, etc.) are OK nil - they come from connections
        data_only_type?(type_str) -> :ok
        # Required configurable types MUST have a value
        true -> {:error, Error.required_error(key)}
      end
    else
      with :ok <- validate_type(key, value, type_str, field_spec),
           :ok <- validate_range(key, value, field_spec),
           :ok <- validate_enum(key, value, field_spec) do
        :ok
      end
    end
  end

  # Type validation

  defp validate_type(_key, nil, _type, _spec), do: :ok

  defp validate_type(key, value, "string", _spec) do
    if is_binary(value) do
      :ok
    else
      {:error, Error.type_error(key, "string", type_of(value))}
    end
  end

  defp validate_type(key, value, "integer", _spec) do
    cond do
      is_integer(value) -> :ok
      is_float(value) && Float.floor(value) == value -> :ok
      is_binary(value) && parseable_integer?(value) -> :ok
      true -> {:error, Error.type_error(key, "integer", type_of(value))}
    end
  end

  defp validate_type(key, value, "float", _spec) do
    cond do
      is_number(value) -> :ok
      is_binary(value) && parseable_float?(value) -> :ok
      true -> {:error, Error.type_error(key, "float", type_of(value))}
    end
  end

  defp validate_type(key, value, "boolean", _spec) do
    # Accept various boolean-like values
    cond do
      is_boolean(value) -> :ok
      value in [0, 1, "true", "false", "0", "1"] -> :ok
      true -> {:error, Error.type_error(key, "boolean", type_of(value))}
    end
  end

  defp validate_type(key, value, "bigint", _spec) do
    cond do
      is_integer(value) -> :ok
      is_binary(value) && parseable_integer?(value) -> :ok
      true -> {:error, Error.type_error(key, "bigint", type_of(value))}
    end
  end

  defp validate_type(key, value, "enum", spec) do
    # spec is guaranteed to have atom keys from normalize_input_spec
    options = spec[:options] || []

    valid_values =
      Enum.map(options, fn opt ->
        # opt maps are also atomized by deep_atomize_keys
        opt[:value]
      end)

    if value in valid_values do
      :ok
    else
      {:error, Error.enum_error(key, value, valid_values)}
    end
  end

  # List types
  defp validate_type(key, value, "list_" <> _item_type, _spec) do
    if is_list(value) do
      :ok
    else
      {:error, Error.type_error(key, "list", type_of(value))}
    end
  end

  # Unknown types - allow through
  defp validate_type(_key, _value, _type, _spec), do: :ok

  # Range validation

  defp validate_range(_key, nil, _spec), do: :ok

  defp validate_range(key, value, spec) when is_number(value) do
    # spec is guaranteed to have atom keys from normalize_input_spec
    min = spec[:min]
    max = spec[:max]

    cond do
      min != nil && value < min ->
        {:error, Error.range_error(key, value, min, max)}

      max != nil && value > max ->
        {:error, Error.range_error(key, value, min, max)}

      true ->
        :ok
    end
  end

  defp validate_range(_key, _value, _spec), do: :ok

  # Enum validation

  defp validate_enum(_key, nil, _spec), do: :ok

  defp validate_enum(key, value, spec) do
    # spec is guaranteed to have atom keys from normalize_input_spec
    options = spec[:options]

    if options && length(options) > 0 do
      valid_values =
        Enum.map(options, fn opt ->
          # opt maps are also atomized by deep_atomize_keys
          opt[:value]
        end)

      if value in valid_values do
        :ok
      else
        {:error, Error.enum_error(key, value, valid_values)}
      end
    else
      :ok
    end
  end

  # Helper functions

  defp normalize_type_string(type) when is_atom(type), do: Atom.to_string(type)
  defp normalize_type_string(type) when is_binary(type), do: String.downcase(type)
  defp normalize_type_string(_), do: "any"

  # Data-only types are any type that is NOT configurable (primitive or enum).
  # This includes model, image, controlnet, lora, etc. - types that come from
  # connections rather than UI widgets. Derived from Types.configurable_type?/1
  # to ensure new data types are automatically handled.
  defp data_only_type?(type) when is_binary(type) do
    not Types.configurable_type?(type)
  end

  defp parseable_integer?(s) when is_binary(s) do
    case Integer.parse(s) do
      {_, ""} -> true
      _ -> false
    end
  end

  defp parseable_float?(s) when is_binary(s) do
    case Float.parse(s) do
      {_, ""} -> true
      # Allow trailing content
      {_, _} -> true
      :error -> false
    end
  end

  defp type_of(value) when is_binary(value), do: "string"
  defp type_of(value) when is_integer(value), do: "integer"
  defp type_of(value) when is_float(value), do: "float"
  defp type_of(value) when is_boolean(value), do: "boolean"
  defp type_of(value) when is_list(value), do: "list"
  defp type_of(value) when is_map(value), do: "map"
  defp type_of(value) when is_nil(value), do: "nil"
  defp type_of(value) when is_atom(value), do: "atom"
  defp type_of(_), do: "unknown"
end
