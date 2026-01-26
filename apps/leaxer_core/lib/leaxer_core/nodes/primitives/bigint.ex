defmodule LeaxerCore.Nodes.Primitives.BigInt do
  @moduledoc """
  Primitive node that outputs a big integer value (for seeds, etc).
  """
  use LeaxerCore.Nodes.Behaviour

  LeaxerCore.Nodes.Behaviour.defprimitive(
    type: "BigInt",
    label: "Big Integer",
    description: "A constant big integer value (useful for seeds)",
    data_type: :bigint,
    default: -1
  )
end
