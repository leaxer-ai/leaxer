defmodule LeaxerCore.Nodes.ValidationTest do
  use ExUnit.Case

  alias LeaxerCore.Nodes.Validation
  alias LeaxerCore.Nodes.Error

  describe "validate_field/3" do
    test "returns error for required configurable field without value or default" do
      # Test string field - should fail
      field_spec = %{type: "string", label: "Required String"}

      assert {:error, %Error{code: :required_field}} =
               Validation.validate_field("test_string", nil, field_spec)

      # Test integer field - should fail
      field_spec = %{type: "integer", label: "Required Integer"}

      assert {:error, %Error{code: :required_field}} =
               Validation.validate_field("test_int", nil, field_spec)

      # Test float field - should fail
      field_spec = %{type: "float", label: "Required Float"}

      assert {:error, %Error{code: :required_field}} =
               Validation.validate_field("test_float", nil, field_spec)
    end

    test "allows nil for data-only types (connected fields)" do
      # Test model field - should pass (comes from connections)
      field_spec = %{type: "model", label: "Model"}
      assert :ok = Validation.validate_field("model", nil, field_spec)

      # Test image field - should pass (comes from connections)
      field_spec = %{type: "image", label: "Image"}
      assert :ok = Validation.validate_field("image", nil, field_spec)

      # Test latent field - should pass (comes from connections)
      field_spec = %{type: "latent", label: "Latent"}
      assert :ok = Validation.validate_field("latent", nil, field_spec)
    end

    test "allows nil when field has default value" do
      # String with default should pass
      field_spec = %{type: "string", label: "String with Default", default: "test"}
      assert :ok = Validation.validate_field("test_string", nil, field_spec)

      # Integer with default should pass
      field_spec = %{type: "integer", label: "Integer with Default", default: 42}
      assert :ok = Validation.validate_field("test_int", nil, field_spec)
    end

    test "validates non-nil values normally" do
      # Valid string should pass
      field_spec = %{type: "string", label: "String"}
      assert :ok = Validation.validate_field("test_string", "hello", field_spec)

      # Invalid type should fail
      field_spec = %{type: "integer", label: "Integer"}

      assert {:error, %Error{code: :type_mismatch}} =
               Validation.validate_field("test_int", "not_a_number", field_spec)
    end
  end

  describe "validate_inputs/3" do
    test "validates multiple fields correctly" do
      inputs = %{}
      config = %{"required_string" => nil, "model" => nil}

      input_spec = %{
        required_string: %{type: "string", label: "Required String"},
        model: %{type: "model", label: "Model"}
      }

      # Should fail due to required_string being nil without default
      assert {:error, %Error{code: :required_field}} =
               Validation.validate_inputs(inputs, config, input_spec)
    end

    test "passes when all required fields have values or defaults" do
      inputs = %{}
      config = %{"required_string" => "hello", "model" => nil}

      input_spec = %{
        required_string: %{type: "string", label: "Required String"},
        model: %{type: "model", label: "Model"}
      }

      assert :ok = Validation.validate_inputs(inputs, config, input_spec)
    end
  end
end
