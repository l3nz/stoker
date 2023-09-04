defmodule StokerTest do
  use ExUnit.Case
  doctest Stoker
  alias Stoker.Activator

  test "greets the world" do
    assert Stoker.hello() == :world
  end

  defmodule CBs do
    @behaviour Stoker

    def init() do
      {:ok, %{mystate: 100, events: []}}
    end

    def event(e, :none, state) do
      {:ok, %{state | mystate: state.mystate + 1, events: [e | state.events]}}
    end

    def event(e, r, state) do
      {:ok, %{state | mystate: state.mystate + 1, events: [{e, r} | state.events]}}
    end

    def next_timer_in(_state), do: :none

    def cluster_valid?(_state), do: :yes
  end

  test "Setup and destruction via callback" do
    assert {:ok, %{mod_state: %{mystate: 101, events: [:start]}, module: StokerTest.CBs} = state0} =
             Activator.init(%{module: CBs})

    assert {:shutdown,
            %{mod_state: %{mystate: 102, events: [{:terminate, :shutdown}, :start]}} = _state1} =
             Activator.terminate(:shutdown, state0)
  end
end
