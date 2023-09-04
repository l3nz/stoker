defmodule Stoker.Activator do
  require Logger

  @moduledoc """
  This GenServer is used to make sure that a process will
  always - and once - be active in the cluster.

  The way this works is that we use the  `:global` naming
  service as a mutex - if the name {Activator, YourModule} can be registered,
  then this server runs the "correct" activator.

  If it cannot be registered, this means somebody else is holding it
  - so we put a monitor on the process who actually registered the name,
  and when it dies, we try registering instead.

  On every application, its Activator (or Activators) are always
  started once per server, so they "idle" ones will just be waiting
  for their turn to take over. If a new server joins a healthy cluster,
  its Activator will simply be waiting.

  Once achieved, the only way to lose one's :master status is by
  death, or disconnection from the main cluster.

  TODO: Decommissioning and cluster limits


  ## The Stoker callback

  A module implementing the Stoker callback will be called
  when some of these events happen:

  - A GenServer becomes master
  - A node joins or leaves the cluster
  - Every few minutes

  ## The state

  This GenServer has a state that can be queried by using the
  `dump/1` system call.

  It contains:

  - `module`: the Stoker module to be called back. This is the
  same module that the Activator is registered under.
  - `mod_state`: a provate state for the Stoker module. This state is
   per-machine - this means that when another node becomes :master,
  - `state`:  :unk,
  - `created_at`: When this GenServer was started (even if not :master)
  - `active_from`:  When this GenServer became :master, or nil
  - `pid`:  The current PID, when :master
  - `monitor`:  The monitor reference to the current :master, if not :master
  - `current_node`: The name of the current node.


  """
  use GenServer, restart: :permanent
  require Logger

  @type level :: :info | :warning | :error

  def start_link(module) when is_atom(module) do
    GenServer.start_link(__MODULE__, %{module: module})
  end

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

    IO.puts("Modue #{i(module)}")
    {:ok, initial_mod_state} = module.init()

    next_timer =
      initial_mod_state
      |> module.next_timer_in()
      |> build_timer()

    state = %{
      module: module,
      mod_state: initial_mod_state,
      state: :unk,
      current_node: Node.self(),
      created_at: DateTime.utc_now(),
      active_from: nil,
      monitor_pid: nil,
      monitor_ref: nil,
      timer_ref: next_timer
    }

    {:ok, register(state)}
  end

  @impl true
  def handle_call(:dump, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _, _}, %{monitor_ref: _mon_ref} = state) do
    {:noreply, register(state)}
  end

  def handle_info({:EXIT, _pid, :name_conflict}, state) do
    # :ok = Supervisor.stop(pid, :shutdown)
    {:stop, {:shutdown, :name_conflict}, state}
  end

  def handle_info(:tick, %{module: module} = state) do
    new_state = event(state, :timer, :none)

    next_timer =
      new_state
      |> module.next_timer_in()
      |> build_timer()

    {:noreply, %{new_state | timer_ref: next_timer}}
  end

  @impl true
  def terminate(reason, state) do
    # :ok = Supervisor.stop(pid, reason)
    new_state = event(state, :terminate, reason)
    {reason, new_state}
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
    new_state = event(state, :start)
    %{new_state | state: :master, active_from: DateTime.utc_now()}
  end

  defp monitor(%{module: module} = state) do
    case whereis(module) do
      :undefined ->
        register(state)

      pid ->
        ref = Process.monitor(pid)
        %{state | state: :waiting, monitor_pid: pid, monitor_ref: ref}
    end
  end

  @spec event(%{}, any, any) :: any
  def event(%{module: module, mod_state: mod_state} = state, event, reason \\ :none) do
    {:ok, new_mod_state} = module.event(event, reason, mod_state)
    %{state | mod_state: new_mod_state}
  end

  defp i(term), do: inspect(term)

  def build_timer(t) when is_integer(t) and t > 0 do
    Process.send_after(self(), :tick, t)
  end

  def build_timer(_), do: nil
end
