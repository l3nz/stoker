defmodule StokerClusterTest do
  use ExUnit.Case, async: false
  doctest Stoker

  test "greets the world" do
    assert Stoker.hello() == :world
  end

  test "something with a required cluster" do
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

    Node.spawn(node1, fn -> Stoker.logMe() end)
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

    p0 =
      Node.spawn(node1, fn ->
        dumpme(:zebra)
      end)

    p1 =
      Node.spawn(node2, fn ->
        dumpme(:zebra)
      end)

    :timer.sleep(1000)
    IO.puts(inspect(Stoker.Cluster.ps()))

    %{current_node: n} = Stoker.Activator.dump(:zebra)
    :ok = LocalCluster.stop_nodes([n])

    :timer.sleep(1000)
    %{current_node: nn} = Stoker.Activator.dump(:zebra)

    IO.puts(inspect(%{prima: n, dopo: nn}))

    :ok = LocalCluster.stop()
  end

  def dump(p) do
    r = GenServer.call(p, :dump)
    IO.puts("PID #{inspect(p)}: #{inspect(r)}")
  end

  def dumpme(module) do
    IO.puts("Starting on #{inspect(Node.self())}")
    r = GenServer.start(Stoker.Activator, %{module: module})
    IO.puts("Got #{inspect(r)} on #{inspect(Node.self())}")
    IO.puts("Nodes #{inspect(Node.list())} on #{inspect(Node.self())}")
    IO.puts("Globals #{inspect(Stoker.Cluster.ps())} on #{inspect(Node.self())}")
  end
end
