defmodule LeaxerCore.Nodes.Types do
  @moduledoc """
  Strict type definitions for node connectors.

  All connector types must be from this enum. Output labels MUST match
  the type name exactly (uppercase). Input connector labels MUST also
  be uppercase.
  """

  @typedoc """
  Valid data types for node connectors.
  """
  @type data_type ::
          :string
          | :integer
          | :float
          | :boolean
          | :bigint
          | :image
          | :mask
          | :segs
          | :model
          | :detector
          | :sam_model
          | :any
          | {:list, data_type()}

  # List of all valid connector types (atoms).
  @valid_types [
    :string,
    :integer,
    :float,
    :boolean,
    :bigint,
    :image,
    :mask,
    :segs,
    :model,
    :detector,
    :sam_model,
    :any
  ]

  @doc """
  Returns the list of valid connector types.
  """
  def valid_types, do: @valid_types

  @doc """
  Checks if a type is valid for connectors.
  """
  def valid_type?({:list, inner_type}), do: valid_type?(inner_type)
  def valid_type?(type) when type in @valid_types, do: true
  def valid_type?(_), do: false

  @doc """
  Converts a type atom to its uppercase label string.
  This is the ONLY valid label for output connectors.

  ## Examples

      iex> Types.type_to_label(:string)
      "STRING"

      iex> Types.type_to_label(:image)
      "IMAGE"

      iex> Types.type_to_label({:list, :string})
      "LIST"
  """
  def type_to_label({:list, _inner}), do: "LIST"

  def type_to_label(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> String.upcase()
  end

  @doc """
  Parameter types (for UI controls, not data connectors).
  These don't need strict labels since they're not connectable.
  """
  @parameter_types [:enum, :model_selector, :comparison]

  def parameter_types, do: @parameter_types

  @doc """
  Checks if a type is a parameter type (not a connector type).
  """
  def parameter_type?(type) when type in @parameter_types, do: true
  def parameter_type?(_), do: false

  @doc """
  Primitive types that require value validation.
  These are configurable via UI widgets and need type checking.
  """
  @primitive_types [:string, :integer, :float, :boolean, :bigint]

  def primitive_types, do: @primitive_types

  @doc """
  Configurable types that require validation during node execution.
  Includes primitives and enum (which validates against options).
  """
  @configurable_types @primitive_types ++ [:enum]

  def configurable_types, do: @configurable_types

  @doc """
  Checks if a type requires value validation.
  Returns true for primitive types and enum.
  Returns false for data-only types (model, image, etc.) that come from connections.
  """
  @spec configurable_type?(atom() | String.t()) :: boolean()
  def configurable_type?(type) when is_atom(type), do: type in @configurable_types

  def configurable_type?(type) when is_binary(type) do
    # Handle string types (list_* prefix means list type, not configurable)
    case type do
      "list_" <> _ -> false
      _ -> String.to_existing_atom(type) in @configurable_types
    end
  rescue
    ArgumentError -> false
  end

  def configurable_type?(_), do: false

  @doc """
  Validates an output spec. Only OUTPUT labels must match the type.
  Input labels can be descriptive (e.g., "Brightness" for type :integer).

  Returns :ok or {:error, list_of_errors}.

  ## Examples

      iex> Types.validate_output_spec(%{
      ...>   value: %{type: :string, label: "STRING"}
      ...> })
      :ok

      iex> Types.validate_output_spec(%{
      ...>   value: %{type: :string, label: "Value"}
      ...> })
      {:error, ["Output 'value': label 'Value' should be 'STRING' for type :string"]}
  """
  def validate_output_spec(spec) when is_map(spec) do
    errors =
      spec
      |> Enum.flat_map(fn {field_name, field_spec} ->
        validate_output_field(field_name, field_spec)
      end)

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc """
  Validates a single output field spec.
  Output labels MUST match the type exactly (UPPERCASE).
  Returns a list of error messages (empty if valid).
  """
  def validate_output_field(field_name, field_spec) when is_map(field_spec) do
    type = field_spec[:type]
    label = field_spec[:label]

    cond do
      # Parameter types (enum, model_selector) can have descriptive labels
      parameter_type?(type) ->
        []

      # Connector types must have uppercase labels matching their type
      valid_type?(type) ->
        expected_label = type_to_label(type)

        if label == expected_label do
          []
        else
          [
            "Output '#{field_name}': label '#{label}' should be '#{expected_label}' for type #{inspect(type)}"
          ]
        end

      # Invalid type
      true ->
        ["Output '#{field_name}': invalid type #{inspect(type)}"]
    end
  end

  def validate_output_field(field_name, _field_spec) do
    ["Output '#{field_name}': invalid field spec (not a map)"]
  end

  @doc """
  Validates a module's output spec and raises if invalid.
  Only OUTPUT labels are validated (must match type).
  Input labels can be descriptive.

  ## Examples

      iex> Types.validate_module!(MyNode)
      :ok

      # Raises ArgumentError if validation fails
  """
  def validate_module!(module) when is_atom(module) do
    output_spec =
      if function_exported?(module, :output_spec, 0) do
        module.output_spec()
      else
        %{}
      end

    case validate_output_spec(output_spec) do
      :ok ->
        :ok

      {:error, errors} ->
        raise ArgumentError,
              "Node #{inspect(module)} has invalid output spec:\n" <>
                Enum.map_join(errors, "\n", &"  - #{&1}")
    end
  end

  @doc """
  Validates all registered nodes in the system.
  Returns a map of type => validation result.
  """
  def validate_all_nodes do
    LeaxerCore.Nodes.Registry.list_types()
    |> Enum.map(fn type ->
      module = LeaxerCore.Nodes.Registry.get_module(type)

      result =
        if module do
          try do
            validate_module!(module)
            :ok
          rescue
            e -> {:error, Exception.message(e)}
          end
        else
          {:error, "Module not found"}
        end

      {type, result}
    end)
    |> Enum.into(%{})
  end
end
