defmodule LeaxerCore.Nodes.Helpers do
  @moduledoc """
  Shared helper functions for node implementations.

  These helpers provide common type coercion and utility functions
  to avoid code duplication across nodes.
  """

  @doc """
  Converts a value to a boolean.

  ## Falsy values
  - `nil`
  - `false`
  - `0` (integer)
  - `0.0` (float)
  - `""` (empty string)
  - `"false"` (string)

  All other values are considered truthy.

  ## Examples

      iex> Helpers.to_bool(true)
      true

      iex> Helpers.to_bool(nil)
      false

      iex> Helpers.to_bool(0)
      false

      iex> Helpers.to_bool("hello")
      true
  """
  @spec to_bool(any()) :: boolean()
  def to_bool(nil), do: false
  def to_bool(false), do: false
  def to_bool(0), do: false
  def to_bool(n) when n == 0.0, do: false
  def to_bool(""), do: false
  def to_bool("false"), do: false
  def to_bool(_), do: true

  @doc """
  Converts a value to a number, returning a default if conversion fails.

  ## Examples

      iex> Helpers.to_number(42)
      42

      iex> Helpers.to_number("3.14")
      3.14

      iex> Helpers.to_number("not a number", 0)
      0

      iex> Helpers.to_number(nil, -1)
      -1
  """
  @spec to_number(any(), number()) :: number()
  def to_number(value, default \\ 0)
  def to_number(n, _default) when is_number(n), do: n
  def to_number(s, default) when is_binary(s), do: parse_number(s, default)
  def to_number(true, _default), do: 1
  def to_number(false, _default), do: 0
  def to_number(_, default), do: default

  @doc """
  Converts a value to an integer, returning a default if conversion fails.

  ## Examples

      iex> Helpers.to_integer(42)
      42

      iex> Helpers.to_integer(3.7)
      3

      iex> Helpers.to_integer("123")
      123
  """
  @spec to_integer(any(), integer()) :: integer()
  def to_integer(value, default \\ 0)
  def to_integer(n, _default) when is_integer(n), do: n
  def to_integer(n, _default) when is_float(n), do: trunc(n)

  def to_integer(s, default) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> default
    end
  end

  def to_integer(true, _default), do: 1
  def to_integer(false, _default), do: 0
  def to_integer(_, default), do: default

  @doc """
  Converts a value to a float, returning a default if conversion fails.

  ## Examples

      iex> Helpers.to_float(3.14)
      3.14

      iex> Helpers.to_float(42)
      42.0

      iex> Helpers.to_float("3.14")
      3.14
  """
  @spec to_float(any(), float()) :: float()
  def to_float(value, default \\ 0.0)
  def to_float(n, _default) when is_float(n), do: n
  def to_float(n, _default) when is_integer(n), do: n * 1.0

  def to_float(s, default) when is_binary(s) do
    case Float.parse(s) do
      {n, _} -> n
      :error -> default
    end
  end

  def to_float(true, _default), do: 1.0
  def to_float(false, _default), do: 0.0
  def to_float(_, default), do: default

  @doc """
  Safely converts any value to a string.

  ## Examples

      iex> Helpers.to_string_safe(nil)
      ""

      iex> Helpers.to_string_safe("hello")
      "hello"

      iex> Helpers.to_string_safe(42)
      "42"
  """
  @spec to_string_safe(any()) :: String.t()
  def to_string_safe(nil), do: ""
  def to_string_safe(v) when is_binary(v), do: v
  def to_string_safe(v) when is_atom(v), do: Atom.to_string(v)
  def to_string_safe(v) when is_number(v), do: to_string(v)
  def to_string_safe(v), do: inspect(v)

  @doc """
  Gets a value from inputs or config, with fallback to default.

  This is the standard pattern for reading node parameters:
  1. Check if value exists in inputs (from connections)
  2. If not, check config (from UI widgets)
  3. If neither, return the provided default

  ## Examples

      iex> Helpers.get_value("a", %{"a" => 10}, %{}, 0)
      10

      iex> Helpers.get_value("a", %{}, %{"a" => 5}, 0)
      5

      iex> Helpers.get_value("a", %{}, %{}, 0)
      0
  """
  @spec get_value(String.t(), map(), map(), any()) :: any()
  def get_value(key, inputs, config, default) do
    inputs[key] || config[key] || default
  end

  @doc """
  Clamps a number to be within a min/max range.

  ## Examples

      iex> Helpers.clamp(5, 0, 10)
      5

      iex> Helpers.clamp(-5, 0, 10)
      0

      iex> Helpers.clamp(15, 0, 10)
      10
  """
  @spec clamp(number(), number(), number()) :: number()
  def clamp(value, min_val, max_val) when is_number(value) do
    value
    |> max(min_val)
    |> min(max_val)
  end

  def clamp(value, min_val, max_val) do
    value
    |> to_number(0)
    |> clamp(min_val, max_val)
  end

  @doc """
  Maps a value from one range to another.

  ## Examples

      iex> Helpers.map_range(0.5, 0, 1, 0, 100)
      50.0

      iex> Helpers.map_range(5, 0, 10, 0, 100)
      50.0
  """
  @spec map_range(number(), number(), number(), number(), number()) :: float()
  def map_range(value, in_min, in_max, out_min, out_max) do
    # Avoid division by zero
    if in_max == in_min do
      out_min
    else
      (value - in_min) / (in_max - in_min) * (out_max - out_min) + out_min
    end
  end

  @doc """
  Recursively converts all string keys in a map to atoms.

  This is used to normalize maps that may come from JSON (string keys)
  to the internal format (atom keys).

  ## Examples

      iex> Helpers.deep_atomize_keys(%{"type" => "string", "label" => "Input"})
      %{type: "string", label: "Input"}

      iex> Helpers.deep_atomize_keys(%{"options" => [%{"value" => "a", "label" => "A"}]})
      %{options: [%{value: "a", label: "A"}]}

      iex> Helpers.deep_atomize_keys(%{type: :string})
      %{type: :string}
  """
  @spec deep_atomize_keys(any()) :: any()
  def deep_atomize_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      atomized_key =
        case key do
          k when is_binary(k) -> String.to_atom(k)
          k when is_atom(k) -> k
          k -> k
        end

      {atomized_key, deep_atomize_keys(value)}
    end)
  end

  def deep_atomize_keys(list) when is_list(list) do
    Enum.map(list, &deep_atomize_keys/1)
  end

  def deep_atomize_keys(value), do: value

  @doc """
  Validates a regex pattern for use in node validate/2 callbacks.

  Returns :ok if the pattern is empty or valid, or an error tuple if invalid.
  This is the standard validation pattern for regex nodes.

  ## Examples

      iex> Helpers.validate_regex("\\d+", %{}, %{})
      :ok

      iex> Helpers.validate_regex("", %{}, %{})
      :ok

      iex> {:error, error} = Helpers.validate_regex("[invalid", %{}, %{})
      iex> error.code
      :invalid_regex
  """
  @spec validate_regex(String.t(), map(), map()) :: :ok | {:error, LeaxerCore.Nodes.Error.t()}
  def validate_regex(key, inputs, config) do
    pattern = get_value(key, inputs, config, "") |> to_string()

    if pattern == "" do
      :ok
    else
      case Regex.compile(pattern) do
        {:ok, _} ->
          :ok

        {:error, {reason, _pos}} ->
          {:error, LeaxerCore.Nodes.Error.regex_error(pattern, to_string(reason))}
      end
    end
  end

  @doc """
  Compiles a regex pattern, returning the compiled regex or an error string.

  Returns {:ok, regex} if valid, {:error, reason} if invalid, or :empty if pattern is empty.
  This is the standard pattern for regex nodes in process/2 callbacks.

  ## Examples

      iex> {:ok, regex} = Helpers.compile_regex("\\d+")
      iex> Regex.match?(regex, "123")
      true

      iex> Helpers.compile_regex("")
      :empty

      iex> {:error, reason} = Helpers.compile_regex("[invalid")
      iex> is_binary(reason)
      true
  """
  @spec compile_regex(String.t()) :: {:ok, Regex.t()} | {:error, String.t()} | :empty
  def compile_regex(pattern) when is_binary(pattern) do
    pattern = String.trim(pattern)

    if pattern == "" do
      :empty
    else
      case Regex.compile(pattern) do
        {:ok, regex} -> {:ok, regex}
        {:error, {reason, _pos}} -> {:error, "Invalid pattern: #{reason}"}
      end
    end
  end

  def compile_regex(nil), do: :empty
  def compile_regex(other), do: compile_regex(to_string(other))

  # Private helpers

  defp parse_number(s, default) when is_binary(s) do
    s = String.trim(s)

    cond do
      String.contains?(s, ".") ->
        case Float.parse(s) do
          {n, _} -> n
          :error -> default
        end

      true ->
        case Integer.parse(s) do
          {n, _} -> n
          :error -> default
        end
    end
  end
end
