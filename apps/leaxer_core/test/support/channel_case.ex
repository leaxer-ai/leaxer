defmodule LeaxerCoreWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.

  Such tests rely on `Phoenix.ChannelTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import LeaxerCoreWeb.ChannelCase

      # The default endpoint for testing
      @endpoint LeaxerCoreWeb.Endpoint
    end
  end

  setup do
    # Ensure the endpoint is started
    {:ok, _} = Application.ensure_all_started(:leaxer_core)
    :ok
  end
end
