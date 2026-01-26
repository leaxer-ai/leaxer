defmodule LeaxerCore.Nodes.Primitives.String do
  @moduledoc """
  Primitive node that outputs a string value.
  """
  use LeaxerCore.Nodes.Behaviour

  LeaxerCore.Nodes.Behaviour.defprimitive(
    type: "String",
    data_type: :string,
    default: "",
    input_opts: [multiline: true]
  )
end
