defmodule Stoker do
  require Logger

  @moduledoc """
  Documentation for `Stoker`.
  """
  @type activator_state :: :master | :watcher | :cluster_change | :timer | :shutdown

  @callback init() :: {:ok, stoker_state :: term} | {:error, reason :: term}
  @callback event(activator_state, reason :: term, state :: term) ::
              {:ok, new_state :: term}
              | {:error, reason :: term}

  @callback next_timer_in(stoker_state :: term) :: integer() | :none
  @callback cluster_valid?(stoker_state :: term) :: :yes | :no

  @doc """
  Hello world.

  ## Examples

      iex> Stoker.hello()
      :world

  """
  def hello do
    :world
  end
end
