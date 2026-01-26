defmodule LeaxerCore.Nodes.Behaviour do
  @moduledoc """
  Behaviour that all nodes must implement.

  ## Usage

  Nodes should use this module to get sensible defaults:

      defmodule MyApp.Nodes.MyNode do
        use LeaxerCore.Nodes.Behaviour

        @impl true
        def type, do: "MyNode"

        @impl true
        def label, do: "My Custom Node"

        @impl true
        def category, do: "Custom"

        @impl true
        def input_spec do
          %{
            input: %{type: :string, label: "Input", default: ""}
          }
        end

        @impl true
        def output_spec do
          %{
            output: %{type: :string, label: "Output"}
          }
        end

        @impl true
        def process(inputs, _config) do
          {:ok, %{"output" => inputs["input"] || ""}}
        end
      end

  ## Category Format

  The `category/0` callback supports hierarchical categories:

  - Simple string: `"Math"` → appears in "Math" category
  - Path string: `"Custom/Text/Transform"` → nested in Custom → Text → Transform
  - List format: `["Custom", "Text", "Transform"]` → same as path string

  ## Input Spec Format

  Each input field can have the following properties:
  - `:type` - The data type (`:string`, `:integer`, `:float`, `:boolean`, `:bigint`, `:enum`, or semantic types like `:model`, `:image`, `:conditioning`, `:latent`)
  - `:label` - Display label for the field
  - `:default` - Default value (makes the field a configurable parameter)
  - `:min` / `:max` - For numeric types, constraints
  - `:step` - For numeric types, increment step
  - `:options` - For `:enum` type, list of `%{value: string, label: string}` maps
  - `:multiline` - For `:string` type, whether to use textarea
  - `:configurable` - Whether the field should show a UI widget (true) or is input-only (false)
  - `:placeholder` - Placeholder text for input fields
  - `:description` - Help text describing the field's purpose

  ## Validation

  Nodes can implement a `validate/2` callback for custom validation before execution.
  The callback receives `(inputs, config)` and should return `:ok` or `{:error, reason}`.

  ## Output Spec Format

  Each output field should have:
  - `:type` - The data type
  - `:label` - Display label for the field
  """

  @type inputs :: map()
  @type config :: map()
  @type output :: map()

  @type input_field_spec :: %{
          required(:type) => atom(),
          required(:label) => String.t(),
          optional(:default) => any(),
          optional(:min) => number(),
          optional(:max) => number(),
          optional(:step) => number(),
          optional(:options) => [%{value: String.t(), label: String.t()}],
          optional(:multiline) => boolean(),
          optional(:configurable) => boolean(),
          optional(:placeholder) => String.t(),
          optional(:description) => String.t()
        }

  @type output_field_spec :: %{
          required(:type) => atom(),
          required(:label) => String.t()
        }

  # Core execution callback
  @callback process(inputs(), config()) :: {:ok, output()} | {:error, atom() | String.t() | map()}

  # Validation callback - called before process
  @callback validate(inputs(), config()) :: :ok | {:error, String.t() | map()}

  # Spec callbacks - can return simple format or enhanced format
  @callback input_spec() :: map()
  @callback output_spec() :: map()

  # Metadata callbacks
  @callback type() :: String.t()
  @callback label() :: String.t()
  @callback category() :: String.t()
  @callback description() :: String.t()
  @callback default_config() :: map()
  @callback ui_component() :: :auto | {:custom, String.t()}
  @callback config_spec() :: map()

  @optional_callbacks [
    validate: 2,
    type: 0,
    label: 0,
    category: 0,
    description: 0,
    default_config: 0,
    ui_component: 0,
    config_spec: 0
  ]

  defmacro __using__(_opts) do
    quote do
      @behaviour LeaxerCore.Nodes.Behaviour

      # Default implementations that can be overridden
      @impl true
      def type do
        __MODULE__
        |> Module.split()
        |> List.last()
      end

      @impl true
      def label, do: type()

      @impl true
      def category, do: "Uncategorized"

      @impl true
      def description, do: ""

      @impl true
      def default_config do
        # Extract defaults from input_spec if available
        try do
          input_spec()
          |> Enum.reduce(%{}, fn {key, spec}, acc ->
            case spec do
              %{default: default} -> Map.put(acc, Atom.to_string(key), default)
              _ -> acc
            end
          end)
        rescue
          # FunctionClauseError: input_spec returned unexpected format
          # UndefinedFunctionError: input_spec not implemented
          FunctionClauseError -> %{}
          UndefinedFunctionError -> %{}
        end
      end

      @impl true
      def ui_component, do: :auto

      @impl true
      def config_spec, do: %{}

      @impl true
      def validate(_inputs, _config), do: :ok

      defoverridable type: 0,
                     label: 0,
                     category: 0,
                     description: 0,
                     default_config: 0,
                     ui_component: 0,
                     config_spec: 0,
                     validate: 2
    end
  end

  @doc """
  Normalizes input spec to enhanced format with atom keys.

  Handles both simple format (%{key: :type}) and enhanced format (%{key: %{type: :type, label: "Label"}}).
  All keys in the output are guaranteed to be atoms, including nested maps like enum options.
  """
  def normalize_input_spec(spec) when is_map(spec) do
    alias LeaxerCore.Nodes.Helpers

    Enum.into(spec, %{}, fn {key, value} ->
      # Ensure top-level key is an atom
      atom_key = ensure_atom_key(key)

      normalized =
        case value do
          # Simple format: %{a: :float}
          type when is_atom(type) ->
            %{type: type, label: atom_key |> Atom.to_string() |> String.capitalize()}

          # Enhanced format: %{a: %{type: :float, label: "A"}}
          %{} = enhanced ->
            # Atomize all keys in the spec map (handles string keys from JSON)
            atomized = Helpers.deep_atomize_keys(enhanced)
            type_value = Map.get(atomized, :type) || Map.get(atomized, "type")
            %{atomized | type: normalize_type(type_value)}

          # Unknown format, try to use as-is
          other ->
            %{
              type: normalize_type(other),
              label: atom_key |> Atom.to_string() |> String.capitalize()
            }
        end

      {atom_key, normalized}
    end)
  end

  @doc """
  Normalizes output spec to enhanced format with atom keys.
  """
  def normalize_output_spec(spec) when is_map(spec) do
    alias LeaxerCore.Nodes.Helpers

    Enum.into(spec, %{}, fn {key, value} ->
      # Ensure top-level key is an atom
      atom_key = ensure_atom_key(key)

      normalized =
        case value do
          type when is_atom(type) ->
            %{type: type, label: atom_key |> Atom.to_string() |> String.capitalize()}

          %{} = enhanced ->
            # Atomize all keys in the spec map
            atomized = Helpers.deep_atomize_keys(enhanced)
            type_value = Map.get(atomized, :type) || Map.get(atomized, "type")
            %{atomized | type: normalize_type(type_value)}

          other ->
            %{
              type: normalize_type(other),
              label: atom_key |> Atom.to_string() |> String.capitalize()
            }
        end

      {atom_key, normalized}
    end)
  end

  @doc """
  Normalizes type to a JSON-serializable string format.
  Converts tuple types like {:list, :string} to strings like "list_string".
  """
  def normalize_type(type) when is_atom(type), do: Atom.to_string(type)

  def normalize_type({:list, item_type}) when is_atom(item_type) do
    "list_#{Atom.to_string(item_type)}"
  end

  def normalize_type({:list, item_type}) do
    "list_#{normalize_type(item_type)}"
  end

  def normalize_type(type) when is_binary(type), do: type
  def normalize_type(_type), do: "any"

  # Helper to ensure a key is an atom
  defp ensure_atom_key(key) when is_atom(key), do: key
  defp ensure_atom_key(key) when is_binary(key), do: String.to_atom(key)
  defp ensure_atom_key(key), do: key

  @doc """
  Normalizes category to a path string format.

  ## Examples

      iex> normalize_category("Math")
      "Math"

      iex> normalize_category("Custom/Text/Transform")
      "Custom/Text/Transform"

      iex> normalize_category(["Custom", "Text", "Transform"])
      "Custom/Text/Transform"
  """
  def normalize_category(category) when is_binary(category), do: category
  def normalize_category(category) when is_list(category), do: Enum.join(category, "/")
  def normalize_category(category) when is_atom(category), do: Atom.to_string(category)
  def normalize_category(_), do: "Uncategorized"

  @doc """
  Parses a category path string into a list of segments.

  ## Examples

      iex> parse_category("Custom/Text/Transform")
      ["Custom", "Text", "Transform"]

      iex> parse_category("Math")
      ["Math"]
  """
  def parse_category(category) when is_binary(category) do
    category
    |> String.split("/")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def parse_category(category) when is_list(category), do: category
  def parse_category(_), do: ["Uncategorized"]

  @doc """
  Defines a primitive node module with minimal boilerplate.

  Primitive nodes output a single configurable value of a specific type.
  This macro generates all required callbacks for the Behaviour.

  ## Options

    * `:type` - The node type string (required)
    * `:label` - Display label (defaults to type)
    * `:description` - Node description (defaults to "A constant {type} value")
    * `:data_type` - The data type atom, e.g. `:string`, `:integer` (required)
    * `:default` - Default value for the input (required)
    * `:input_opts` - Additional options for input_spec, e.g. `[multiline: true]` (optional)

  ## Example

      defmodule MyApp.Nodes.Primitives.String do
        use LeaxerCore.Nodes.Behaviour

        LeaxerCore.Nodes.Behaviour.defprimitive(
          type: "String",
          data_type: :string,
          default: "",
          input_opts: [multiline: true]
        )
      end
  """
  defmacro defprimitive(opts) do
    type = Keyword.fetch!(opts, :type)
    label = Keyword.get(opts, :label, type)
    data_type = Keyword.fetch!(opts, :data_type)
    default = Keyword.fetch!(opts, :default)
    description = Keyword.get(opts, :description, "A constant #{String.downcase(type)} value")
    input_opts = Keyword.get(opts, :input_opts, [])

    # Convert input_opts to escaped key-value pairs for merging at runtime
    escaped_input_opts = Macro.escape(Enum.into(input_opts, %{}))

    quote do
      @impl true
      @spec type() :: String.t()
      def type, do: unquote(type)

      @impl true
      @spec label() :: String.t()
      def label, do: unquote(label)

      @impl true
      @spec category() :: String.t()
      def category, do: "Primitives"

      @impl true
      @spec description() :: String.t()
      def description, do: unquote(description)

      @impl true
      @spec input_spec() :: %{value: map()}
      def input_spec do
        # Build map at runtime to properly evaluate values like -1
        base = %{type: unquote(data_type), label: "VALUE", default: unquote(default)}
        %{value: Map.merge(base, unquote(escaped_input_opts))}
      end

      @impl true
      @spec output_spec() :: %{value: map()}
      def output_spec do
        %{value: %{type: unquote(data_type), label: "VALUE"}}
      end

      @impl true
      @spec process(map(), map()) :: {:ok, map()}
      def process(_inputs, config) do
        value = config["value"] || unquote(default)
        {:ok, %{"value" => value}}
      end
    end
  end
end
