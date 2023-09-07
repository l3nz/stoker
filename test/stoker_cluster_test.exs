defmodule StokerClusterTest do
  # test/stoker_cluster_test.exs:146
  require Logger
  use ExUnit.Case, async: false
  doctest Stoker

  def small_sleep(), do: :timer.sleep(100)

  @tag :with_epmd
  test "Let's learn how Local Cluster works", %{module: mod, test: name} do
    Logger.error("=== #{mod}: Starting #{name}")
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
  test "something else with a required cluster", %{module: mod, test: name} do
    Logger.error("=== #{mod}: Starting #{name}")
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

    def event(state, e, r) do
      Logger.warn("Event #{inspect(e)} on #{inspect(Node.self())}")
      {:ok, %{state | mystate: state.mystate + 1, events: [e | state.events]}}
    end

    def next_timer_in(_state), do: :none

    def cluster_valid?(_state), do: :yes
  end

  defmodule CB_Timer do
    @behaviour Stoker

    def init() do
      {:ok, %{mystate: 100, events: []}}
    end

    def event(state, e, :none) do
      {:ok, %{state | mystate: state.mystate + 1, events: [e | state.events]}}
    end

    def event(state, e, r) do
      {:ok, %{state | mystate: state.mystate + 1, events: [{e, r} | state.events]}}
    end

    def next_timer_in(_state), do: 20

    def cluster_valid?(_state), do: :yes
  end

  @tag :with_epmd
  test "Stoker on a 2 cluster node", %{module: mod, test: name} do
    Logger.error("=== #{mod}: Starting #{name}")
    :ok = LocalCluster.start()

    nodes =
      LocalCluster.start_nodes("mcc", 2,
        files: [
          __ENV__.file
        ]
      )

    [node1, node2] = nodes

    spawn_remotely(node1, CBs)
    spawn_remotely(node2, CBs)

    small_sleep()

    %{current_node: n} = Stoker.Activator.dump(CBs)
    Logger.error("Stopping node")
    :ok = LocalCluster.stop_nodes([n])

    small_sleep()
    %{current_node: nn} = Stoker.Activator.dump(CBs)

    assert n != nn, "Node changed"

    :ok = LocalCluster.stop()
  end

  @tag :with_epmd
  test "Stoker on a 2 cluster node, stopping other node", %{module: mod, test: name} do
    Logger.error("=== #{mod}: Starting #{name}")
    :ok = LocalCluster.start()

    nodes =
      LocalCluster.start_nodes("mcc", 2,
        files: [
          __ENV__.file
        ]
      )

    [node1, node2] = nodes

    spawn_remotely(node1, CBs)
    spawn_remotely(node2, CBs)

    small_sleep()
    %{current_node: curr_node} = Stoker.Activator.dump(CBs)

    otherNode =
      nodes
      |> Enum.filter(fn node -> node != curr_node end)
      |> List.first()

    Logger.error("Stopping other node")
    :ok = LocalCluster.stop_nodes([otherNode])

    small_sleep()
    %{current_node: nn} = evts = Stoker.Activator.dump(CBs)

    assert curr_node == nn, "Node not changed"
    assert %{mod_state: %{events: [:cluster_change, :now_leader]}} = evts

    :ok = LocalCluster.stop()
  end

  @tag :with_epmd
  test "Stoker on a 2 cluster node with timers", %{module: mod, test: name} do
    Logger.error("=== #{mod}: Starting #{name}")
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

    small_sleep()

    %{current_node: n, mod_state: %{events: evts}} = Stoker.Activator.dump(CB_Timer)
    # l'ultimo evento è un timer
    assert [:timer | _] = evts

    Logger.error("Stopping node")
    :ok = LocalCluster.stop_nodes([n])

    small_sleep()
    %{current_node: nn} = _r = Stoker.Activator.dump(CB_Timer)

    assert n != nn, "Node changed"

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
