defmodule LeaxerCore.Nodes.Primitives.Float do
  @moduledoc """
  Primitive node that outputs a float value.
  """
  use LeaxerCore.Nodes.Behaviour

  LeaxerCore.Nodes.Behaviour.defprimitive(
    type: "Float",
    description: "A constant floating-point value",
    data_type: :float,
    default: 0.0,
    input_opts: [step: 0.1]
  )
end
