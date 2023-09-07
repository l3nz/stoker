defmodule Stoker do
  import SayCheezEx, only: [uml: 1]
  require Logger

  @moduledoc """
  Stoker makes sure that your cluster keeps running, no matter
  what happens.

  One of the big ideas behind Elixir/Erlang is distribution as
  a way to address faults - if you have multiple servers running
  in a cluster, and one of them dies, the others keep on churning.
  This is quite easy to do when those servers are all alike, e.g.
  a webserver running a Phoenix app - wherever the request lands,
  it is processed there. But you can do this easily is any environment -
  Java, Go, whatever.

  What is more interesting in the Elixir/Erlang
  world is the ability to have **cluster-unique processes** that end up
  being distribuited and surviving machine faults. This happens
  a lot of times to me - I often have to write data import jobs
  thet retrieve, rewrite and forward data. I want them to be
  always available, will accept small glitches (because a process may
  die on my end or on the other end) but I never want two processes
  to run the same job at the same time.

  Stoker is the foundation upon which this is built. A single
  instance of Stoker is always running in the cluster - and it it
  dies, another one is restarted on a surviving node. It has
  full visibility of the cluster, and a list of jobs to assure being up.
  It will try to make sure that all of them are available, and
  if some are missing, will restart them on one of the available nodes.
  Usually, this happens by delegating them to a local DynamicSupervisor,
  that once started will do its magic to keep the process running.

  Every once in a while, or when receiving a wake-up signal, it
  will wake up again and make sure that
  everything is in order.  This is beacuse it is quite likely that
  you have a dynamic list of jobs you want to run - e.g. you
  may add or remove them for a database table - so Stoker will
  react automatically when you add a new one. It is also possible
  that some external conditions had the DynamicSupervisor give up,
  so it may be appropriate to restart the process on another random
  node and try again.

  ## Implementation

  Here is a typical scenario running Stoker. Our application
  runs on two nodes, and our goal is to keep Process X alive
  somewhere.

  #{uml("""
    skinparam linetype ortho

    frame "Node 1" {
      Component [Application] as A1 #Yellow
      Component [Dyn.Sup.] as D1 #Yellow

      Component [Stoker.Activator] as SA #Red
      note left of SA: Leader

      Component [Your module] as Y
      note bottom of Y : Custom logic implementing behavior @Stoker

    }

    frame "Node 2" {
      Component [Application] as A2 #Yellow
      Component [Stoker.Activator] as SP #Gray
      note right of SP: Follower

      Component [Dyn.Sup.] as D2 #Yellow
      Component [Process X] as PX

    }

    A1 .. D1
    A1 .. SA
    SA -- Y
    SA .> D2

    A2 .. SP
    A2 .. D2
    D2 -down-> PX
    SP -> SA : monitors



  """)}

  On start-up, the Stoker Activator process on node 1 becomes active (we say it's
  a Leader),
  and the one on node 2, that was started a few seconds after that,
  noticed that there was already
  a running one, and became a Follower of the Leader,
  waiting for its brother on node 1 to terminate.

  So the process on node 1 called into your module - one you
  created implementing the
  Stoker behavior - and asked it to check and
  activate all processes it needed to. Your module choose a random
  DynamicSupervisor out of the node pool, selected the one on node 2,
   and asked it to
  start supervising Process X.

  Every once in a while, Stoker on node 1 wakes up and calls your module
  to make sure that all processes that are supposed to be alive actually are;
  if not, they are started again.

  ### What happens if node 1 dies?

  Stoker on node 2 will notice that its brother failed, so it will
  become a leader. It will then trigger your module, that will notice that
  Process X is available, and do nothing more. If there were some
  persistent processes on node 1, they would be started again on node 2,
  as that is the only remaining node.

  If node 1 restarts, Stoker on node 1 will notice that there is already
  a Leader on node 2, so it will become a Follower - it will
  put a watch on the Leader and will wait for
  it to become unavailable.

  ### What happens if node 2 dies?

  If node 2 dies, Stoker on node 1 - that is already a Leader -
  receives an update that the
  cluster composition changed; it will trigger your module, that will
  notice that Process X is not running, and will start it again
  on the only remaining node.

  When node 2 restarts, Stoker on it will notice that there is already
  a Leader on node 1, and will become a Follower.


  ### What happens if we add node 3?

  If we add a new node, Stoker on node 1 receives an update that the
  cluster composition changed; it will trigger your module, that will
  notice that Process X is still running, and won't do anything.

  The new Stoker on node 3 will become a Follower, like the one on
  node 2 is.
  If node 1 becomes unavailable, both will race to become the new
  Leader; one of them will succeed, and the other one will become a
  Follower.

  As node 3 has its own DynamicSupervisor, it will become eligible
  to run new processes as the need arises.

  ### Network partitions

  This is the tough one.

  On a netsplit, both nodes keep running but none of them sees
  the other one. In this case, each Stoker will become Leader
  and run Process X on its own pool. In any case, your module will
  be notified, so you could decide what to do - terminate all processes,
  wait a bit, whatever.

  When the netsplit heals, one of the Stoker processes is terminated,
  and the same happens for every processed that has registered twice.
  So one of the processes will remain leader, the one that was terminated
  will respawn and become a follower.

  ### Rebalancing

  There is no facility to do rebalancing yet, but as your module is
  triggered on network events, you could do that.

  ## Guaranteeing uniqueness

  To guarantee uniqueness of running processes, we use the battle-tested
  `:global` naming module, that will make sure that a name is registered
  only once.

  It's not very fast, but can manage thousands of registrations per
  seconds on moderately-sized clusters and it's supposedly very
  reliable, so it's good enough for what
  we need here.

  # Using in practice

  ## Start-up within an application

  The Activator is implemented by `Stoker.Activator`,
  that is a GenServer that will call your Stoker behavior
  when needed.

  So in your Application sequence you will need
  to add:

  ````
  {DynamicSupervisor, [name: {StokerDS, node()}, strategy: :one_for_one]},
  {Stoker.Activator, xx.MyStoker},
  ````

  In the first row, we ask each node of the cluster
  to start up and register on `:global` a `DynamicSupervisor`
  that is called `{StokerDS, node1@cluster}`. This way
  we can address it easily from any node in the cluster.

  On the second row, we start a `Stoker.Activator`  GenServer
  that, when acting as a leader, registers
  itself as `{Stoker.Activator, your_module_name}`,
  so you can definitely have more than one running on the
  same cluster.

  ## The Stoker life-cycle

  The life-cycle of a Stoker call-back is modelled on
  the one that a `GenServer` offers.

  There is a state term that can be used to store a
  state to be held between multiple calls (but only on
  the same server - the state is not shared with followers).


  #{uml("""

    state fork_state <<fork>>
    [*] --> fork_state
    fork_state --> leader : now_leader
    fork_state --> follower : now_follower
    follower --> leader : now_leader
    leader --> leader : cluster_change, timer, trigger
    leader --> splitbrain : cluster_split
    splitbrain --> leader : cluster_change
    splitbrain --> [*] : shutdown
    leader --> [*] : shutdown
    follower --> [*] : shutdown


  """)}




  """
  @type activator_event ::
          :now_leader
          | :now_follower
          | :cluster_change
          | :cluster_split
          | :timer
          | :trigger
          | :shutdown

  @type activator_state ::
          :leader | :follower

  @doc """

  """

  @callback init() :: {:ok, stoker_state :: term} | {:error, reason :: term}

  @doc """
  """

  @callback event(stoker_state :: term, event_type :: activator_event, reason :: term) ::
              {:ok, new_state :: term}
              | {:error, reason :: term}

  @doc """
  """

  @callback next_timer_in(stoker_state :: term) :: integer() | :none
  @doc """
  In front of a cluster change, determines whether
  we are on the losing side of a netsplit situation or not.

  For example, if we have a three node cluster, we may protect
  against netsplits by saying that any node left that has
  less than two nodes is on the losing side of a netsplit,
  so should terminate all processes.

  If the answer is:

  - `:yes` - calls event `:cluster_change`
  - `:cluster_split` - the cluster is invalid, that is
    we are on the losing side of a net-split, so call
    event `:cluster_split` so local processes can be terminated
  - `no` - the cluster is invalid, but do not raise any event


  """
  @callback cluster_valid?(stoker_state :: term) :: :yes | :no | :cluster_split

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
