defmodule LeaxerCore.Nodes.Primitives.Boolean do
  @moduledoc """
  Primitive node that outputs a boolean value.
  """
  use LeaxerCore.Nodes.Behaviour

  LeaxerCore.Nodes.Behaviour.defprimitive(
    type: "Boolean",
    description: "A constant boolean value (true/false)",
    data_type: :boolean,
    default: false
  )
end
