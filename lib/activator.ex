defmodule Stoker.Activator do
  require Logger

  @moduledoc """
  Documentation for `Stoker`.
  """
  use GenServer
  require Logger

  def dump(p) when is_pid(p) do
    GenServer.call(p, :dump)
  end

  def dump(module) when is_atom(module) do
    GenServer.call(whereis(module), :dump)
  end

  def whereis(module) when is_atom(module) do
    :global.whereis_name({__MODULE__, module})
  end

  @impl true
  def init(%{module: module}) do
    Process.flag(:trap_exit, true)

    state = %{
      module: module,
      state: :unk,
      active_from: 0,
      pid: nil,
      monitor: nil,
      current_node: Node.self()
    }

    {:ok, register(state)}
  end

  @impl true
  def handle_call(:dump, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _, _}, %{monitor: _mon_ref} = state) do
    {:noreply, register(state)}
  end

  def handle_info({:EXIT, _pid, :name_conflict}, %{pid: pid} = state) do
    :ok = Supervisor.stop(pid, :shutdown)
    {:stop, {:shutdown, :name_conflict}, Map.delete(state, :pid)}
  end

  @impl true
  def terminate(reason, %{pid: pid}) do
    :ok = Supervisor.stop(pid, reason)
  end

  def terminate(_, _), do: nil

  defp name(%{module: module}) do
    {__MODULE__, module}
  end

  defp handle_conflict(_name, pid1, pid2) do
    Process.exit(pid2, :name_conflict)
    pid1
  end

  defp register(state) do
    case :global.register_name(name(state), self(), &handle_conflict/3) do
      :yes -> started(state)
      :no -> monitor(state)
    end
  end

  defp started(state) do
    %{state | pid: self(), state: :master}
  end

  defp monitor(%{module: module} = state) do
    case whereis(module) do
      :undefined ->
        register(state)

      pid ->
        ref = Process.monitor(pid)
        %{state | state: :waiting, pid: pid, monitor: ref}
    end
  end
end
