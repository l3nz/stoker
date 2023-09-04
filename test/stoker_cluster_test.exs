defmodule StokerClusterTest do
  require Logger
  use ExUnit.Case, async: false
  doctest Stoker

  @tag :with_epmd
  test "Let's learn how LOcal Cluster works" do
    :ok = LocalCluster.start()
    nodes = LocalCluster.start_nodes("my-cluster", 3)

    IO.puts(inspect(nodes))
    [node1, node2, node3] = nodes

    assert Node.ping(node1) == :pong
    assert Node.ping(node2) == :pong
    assert Node.ping(node3) == :pong

    :ok = LocalCluster.stop_nodes([node1])

    IO.puts(inspect(Node.list()))

    assert Node.ping(node1) == :pang
    assert Node.ping(node2) == :pong
    assert Node.ping(node3) == :pong

    :ok = LocalCluster.stop()

    assert Node.ping(node1) == :pang
    assert Node.ping(node2) == :pang
    assert Node.ping(node3) == :pang
  end

  @tag :with_epmd
  test "something else with a required cluster" do
    :ok = LocalCluster.start()

    nodes =
      LocalCluster.start_nodes("my-clusterb", 6,
        files: [
          __ENV__.file
        ]
      )

    IO.puts(inspect(nodes))
    [node1, node2, node3, _node4, _node5, _node6] = nodes

    assert Node.ping(node1) == :pong
    assert Node.ping(node2) == :pong
    assert Node.ping(node3) == :pong

    Node.spawn(node1, fn -> Logger.warn("H3ll0") end)
    # Node.spawn( node2, fn -> Stoker.logMe end)

    caller = self()

    Node.spawn(node1, fn ->
      send(caller, :from_node_1)
    end)

    Node.spawn(node2, fn ->
      send(caller, :from_node_2)
    end)

    Node.spawn(node3, fn ->
      send(caller, :from_node_3)
    end)

    assert_receive :from_node_1
    assert_receive :from_node_2
    assert_receive :from_node_3

    :ok = LocalCluster.stop()
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

  defmodule CB_Timer do
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

    def next_timer_in(_state), do: 50

    def cluster_valid?(_state), do: :yes
  end

  @tag :with_epmd
  test "Stoker on a 2 cluster node" do
    :ok = LocalCluster.start()

    nodes =
      LocalCluster.start_nodes("mcc", 2,
        files: [
          __ENV__.file
        ]
      )

    [node1, node2] = nodes

    assert Node.ping(node1) == :pong
    assert Node.ping(node2) == :pong

    spawn_remotely(node1, CBs)
    spawn_remotely(node2, CBs)

    :timer.sleep(1000)
    IO.puts(inspect(Stoker.Cluster.ps()))

    %{current_node: n} = Stoker.Activator.dump(CBs)
    :ok = LocalCluster.stop_nodes([n])

    :timer.sleep(1000)
    %{current_node: nn} = Stoker.Activator.dump(CBs)

    IO.puts(inspect(%{prima: n, dopo: nn}))

    :ok = LocalCluster.stop()
  end

  @tag :with_epmd
  test "Stoker on a 2 cluster node with timers" do
    :ok = LocalCluster.start()

    nodes =
      LocalCluster.start_nodes("mxx", 2,
        files: [
          __ENV__.file
        ]
      )

    [node1, node2] = nodes

    assert Node.ping(node1) == :pong
    assert Node.ping(node2) == :pong

    spawn_remotely(node1, CB_Timer)
    spawn_remotely(node2, CB_Timer)

    :timer.sleep(1000)

    %{current_node: n, mod_state: %{events: evts}} = Stoker.Activator.dump(CB_Timer)
    # l'ultimo evento è un timer
    assert [:timer | _] = evts

    :ok = LocalCluster.stop_nodes([n])

    :timer.sleep(1000)
    %{current_node: nn} = Stoker.Activator.dump(CB_Timer)

    IO.puts(inspect(%{prima: n, dopo: nn}))

    :ok = LocalCluster.stop()
  end

  def dump(p) do
    r = GenServer.call(p, :dump)
    IO.puts("PID #{inspect(p)}: #{inspect(r)}")
  end

  def spawn_remotely(node, module),
    do:
      Node.spawn(node, fn ->
        start_remotely(module)
      end)

  def start_remotely(module) do
    n = "[#{inspect(Node.self())}] -"
    r = GenServer.start(Stoker.Activator, %{module: module})
    Logger.warn("#{n} Genserver started #{inspect(r)}")

    Logger.warn(
      "#{n} Node list #{inspect(Node.list())} - Globals: #{inspect(Stoker.Cluster.ps())}"
    )
  end
end
