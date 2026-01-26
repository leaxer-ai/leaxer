defmodule LeaxerCore.Nodes.BehaviourTest do
  use ExUnit.Case, async: true

  alias LeaxerCore.Nodes.Behaviour

  # Test module using defprimitive with a negative default value.
  # This is a regression test for a bug where negative defaults like -1
  # were incorrectly handled by Macro.escape at compile time, resulting
  # in malformed AST nodes instead of the actual negative value.
  defmodule NegativeDefaultPrimitive do
    use LeaxerCore.Nodes.Behaviour

    LeaxerCore.Nodes.Behaviour.defprimitive(
      type: "NegativeDefault",
      data_type: :integer,
      default: -1
    )
  end

  # Test module with negative float default
  defmodule NegativeFloatPrimitive do
    use LeaxerCore.Nodes.Behaviour

    LeaxerCore.Nodes.Behaviour.defprimitive(
      type: "NegativeFloat",
      data_type: :float,
      default: -0.5,
      input_opts: [step: 0.1]
    )
  end

  # Test module with input_opts containing positive values only
  # Note: negative values in input_opts have a known issue (Macro.escape preserves AST)
  # This test verifies input_opts work with positive values alongside negative defaults
  defmodule NegativeWithOpts do
    use LeaxerCore.Nodes.Behaviour

    LeaxerCore.Nodes.Behaviour.defprimitive(
      type: "NegativeWithOpts",
      data_type: :integer,
      default: -100,
      input_opts: [min: 0, max: 1000]
    )
  end

  describe "defprimitive macro with negative defaults" do
    test "input_spec returns correct negative integer default" do
      spec = NegativeDefaultPrimitive.input_spec()

      # The bug caused default to be an AST tuple like {:-, [...], [1]}
      # instead of the integer -1
      assert spec == %{
               value: %{type: :integer, label: "VALUE", default: -1}
             }

      # Explicitly verify default is an integer, not a tuple
      assert is_integer(spec.value.default)
      assert spec.value.default == -1
    end

    test "input_spec returns correct negative float default with input_opts" do
      spec = NegativeFloatPrimitive.input_spec()

      assert spec == %{
               value: %{type: :float, label: "VALUE", default: -0.5, step: 0.1}
             }

      # Explicitly verify default is a float, not a tuple
      assert is_float(spec.value.default)
      assert spec.value.default == -0.5
    end

    test "input_spec correctly merges input_opts with negative default" do
      spec = NegativeWithOpts.input_spec()

      assert spec == %{
               value: %{type: :integer, label: "VALUE", default: -100, min: 0, max: 1000}
             }

      # Verify the negative default is correctly evaluated as an integer
      assert is_integer(spec.value.default)
      assert spec.value.default == -100

      # Verify input_opts values are correctly merged
      assert is_integer(spec.value.min)
      assert is_integer(spec.value.max)
      assert spec.value.min == 0
      assert spec.value.max == 1000
    end

    test "process uses negative default when config value is missing" do
      config = %{}
      assert {:ok, %{"value" => -1}} = NegativeDefaultPrimitive.process(%{}, config)
    end

    test "process uses negative default when config value is nil" do
      config = %{"value" => nil}
      assert {:ok, %{"value" => -1}} = NegativeDefaultPrimitive.process(%{}, config)
    end

    test "process returns provided config value over negative default" do
      config = %{"value" => 42}
      assert {:ok, %{"value" => 42}} = NegativeDefaultPrimitive.process(%{}, config)
    end
  end

  describe "defprimitive macro metadata callbacks" do
    test "type returns correct string" do
      assert NegativeDefaultPrimitive.type() == "NegativeDefault"
    end

    test "label defaults to type" do
      assert NegativeDefaultPrimitive.label() == "NegativeDefault"
    end

    test "category returns Primitives" do
      assert NegativeDefaultPrimitive.category() == "Primitives"
    end

    test "description is auto-generated from type" do
      assert NegativeDefaultPrimitive.description() == "A constant negativedefault value"
    end

    test "output_spec matches data_type" do
      assert NegativeDefaultPrimitive.output_spec() == %{
               value: %{type: :integer, label: "VALUE"}
             }
    end
  end

  describe "normalize_input_spec/1" do
    test "normalizes simple format to enhanced format" do
      simple = %{a: :float, b: :string}
      normalized = Behaviour.normalize_input_spec(simple)

      # Simple format preserves atom types
      assert normalized == %{
               a: %{type: :float, label: "A"},
               b: %{type: :string, label: "B"}
             }
    end

    test "normalizes enhanced format and converts type to string" do
      enhanced = %{value: %{type: :integer, label: "Custom Label", default: 5}}
      normalized = Behaviour.normalize_input_spec(enhanced)

      # Enhanced format converts type to string via normalize_type
      assert normalized == %{
               value: %{type: "integer", label: "Custom Label", default: 5}
             }
    end

    test "converts string keys to atom keys" do
      with_string_keys = %{"input" => %{"type" => :float, "label" => "Input Value"}}
      normalized = Behaviour.normalize_input_spec(with_string_keys)

      # String keys are converted to atoms, type is converted to string
      assert normalized == %{
               input: %{type: "float", label: "Input Value"}
             }
    end
  end

  describe "normalize_category/1" do
    test "passes through simple string" do
      assert Behaviour.normalize_category("Math") == "Math"
    end

    test "passes through path string" do
      assert Behaviour.normalize_category("Custom/Text/Transform") == "Custom/Text/Transform"
    end

    test "joins list into path string" do
      assert Behaviour.normalize_category(["Custom", "Text", "Transform"]) ==
               "Custom/Text/Transform"
    end

    test "converts atom to string" do
      assert Behaviour.normalize_category(:Math) == "Math"
    end

    test "returns Uncategorized for invalid input" do
      assert Behaviour.normalize_category(123) == "Uncategorized"
    end
  end

  describe "parse_category/1" do
    test "splits path string into list" do
      assert Behaviour.parse_category("Custom/Text/Transform") == [
               "Custom",
               "Text",
               "Transform"
             ]
    end

    test "returns single-element list for simple string" do
      assert Behaviour.parse_category("Math") == ["Math"]
    end

    test "trims whitespace from segments" do
      assert Behaviour.parse_category("  Custom / Text / Transform  ") == [
               "Custom",
               "Text",
               "Transform"
             ]
    end

    test "passes through list unchanged" do
      assert Behaviour.parse_category(["A", "B", "C"]) == ["A", "B", "C"]
    end

    test "returns Uncategorized for invalid input" do
      assert Behaviour.parse_category(123) == ["Uncategorized"]
    end
  end
end
