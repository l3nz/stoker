defmodule Stoker.Cluster do
  require Logger

  @moduledoc """
  Functions to handle clusters.
  """

  @doc """
  Show all `:global` names and their PIDs.
  """
  def ps() do
    :global.registered_names()
    |> Enum.map(fn n ->
      {n, :global.whereis_name(n)}
    end)
  end
end
