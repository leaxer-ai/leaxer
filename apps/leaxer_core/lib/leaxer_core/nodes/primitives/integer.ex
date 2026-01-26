defmodule LeaxerCore.Nodes.Primitives.Integer do
  @moduledoc """
  Primitive node that outputs an integer value.
  """
  use LeaxerCore.Nodes.Behaviour

  LeaxerCore.Nodes.Behaviour.defprimitive(
    type: "Integer",
    data_type: :integer,
    default: 0
  )
end
