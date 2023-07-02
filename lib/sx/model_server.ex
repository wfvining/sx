defmodule Sx.ModelServer do
  @moduledoc """

  This server manages the state, inputs, and outputs for a single
  model. The model can be either a network or atomic; however, only
  certain functions apply to each model type.

  ## Atomic Models

  Atomic models are the core of the simulation. They are the ultimate
  destination of input and the source of all output. As the simulation
  advances it calls `Sx.ModelServer.delta/1` to update the state of
  every atomic model. Output from the models is cached in the server,
  meaning that the actual `Sx.Atomic.output/1` function is only called
  once per-timestep.

  ## Network models

  Network models provide a means for connecting atomic models. When
  input arrives at a network it is routed through the network to the
  appropriate atomic models using `Sx.ModelServer.route/3`. When the
  children of a network (atomic or network models) produce output, it
  is routed through the network's coupling function (implemented in
  the `Sx.Network.route/3` protocol function) to transform it into
  either input for other models within the network or output from the
  network itself.

  """

  use GenServer

  require Logger

  alias Sx.Model
  alias Sx.Network
  alias Sx.Atomic

  def start_link(model) do
    GenServer.start_link(__MODULE__, model, [])
  end

  def type(server), do: GenServer.call(server, :type)

  @doc """
  Return all the atomic elements of the model managed by this
  server. If the model is atomic then only the model is returned; if
  it is a network then every atomic model contained within it and its
  sub-networks it returned.
  """
  @spec all_atomics(pid) :: [pid]
  def all_atomics(server), do: GenServer.call(server, :all_atomics)

  @doc """
  Add input to the model for the next step.
  """
  @spec add_input(pid, any) :: :ok
  def add_input(server, input), do: GenServer.cast(server, {:add_input, input})

  @doc """
  Compute the models next state with the input that was set using
  `Sx.ModelServer.add_input/2`. This function is only applicable to
  atomic models, as network models are advanced by individually
  calling `ModelServer.delta/1` on all their atomic children.
  """
  @spec delta(pid) :: :ok
  def delta(server), do: GenServer.cast(server, :delta)

  @doc """
  Return the model's output bag. This function only applies to atomic
  models.
  """
  @spec output(pid) :: [any]
  def output(server), do: GenServer.call(server, :output)

  @doc """
  Return the parent of this model. If this model does not have a
  parent (i.e. it is the top level model in the simulation) then `nil`
  is returned.
  """
  @spec parent(pid) :: pid | nil
  def parent(server), do: GenServer.call(server, :get_parent)

  @doc """
  Set the parent of the model. `parent` should be the pid of the model
  server for the network model that contains this model.
  """
  @spec set_parent(pid, pid) :: :ok
  def set_parent(server, parent), do: GenServer.cast(server, {:set_parent, parent})

  @doc """
  Route input through a network. The model managed by `server` must be
  a network model.
  """
  @spec route(pid, pid, any) :: {:ok, [{model :: pid, value :: any}]} | {:error, :atomic}
  def route(server, source, value) do
    GenServer.call(server, {:route, source, value})
  end

  @doc """
  Set the event manager that should be notified when the model changes state.
  """
  @spec set_event_manager(pid, pid) :: :ok
  def set_event_manager(server, event_manager) do
    GenServer.cast(server, {:set_event_manager, event_manager})
  end

  @impl true
  def init(model) do
    if Model.type(model) == :network do
      Enum.each(Network.children(model), &set_parent(&1, self()))
    end
    {:ok, %{model: model, input: [], parent: nil, event_manager: nil}}
  end

  @impl true
  def handle_call(:all_atomics, _from, state) do
    atomics = case Model.type(state.model) do
      :atomic -> [self()]
      :network ->
        atomic_children(state.model)
    end
    {:reply, atomics, state}
  end

  def handle_call(:output, _from, state) do
    if Model.type(state.model) == :network do
      Logger.error(
        "ModelServer.output/1 called on a network model."
        <> " This function can only be used on atomic models."
      )
      {:reply, {:error, :network}, state}
    else
      {newmodel, output} = Atomic.output(state.model)
      {:reply, output, %{state | model: newmodel}}
    end
  end

  def handle_call(:get_parent, _from, %{parent: parent} = state) do
    {:reply, parent, state}
  end

  def handle_call({:route, source, value}, _from, state) do
    if Model.type(state.model) == :atomic do
      Logger.error(
        "ModelServer.route/3 called on an atomic model. "
        <> " This function can only be used on network models."
      )
      {:reply, {:error, :atomic}, state}
    else
      r = Network.route(state.model, self(), source, value)
      {:reply, {:ok, r}, state}
    end
  end

  def handle_call(:type, _from, state) do
    {:reply, Model.type(state.model), state}
  end

  @impl true
  def handle_cast({:add_input, x}, state) do
    {:noreply, %{state | input: [x | state.input]}}
  end

  def handle_cast(:delta, state) do
    if Model.type(state.model) == :network do
      Logger.error(
        "ModelServer.delta/1 called on a network model. "
        <> "Only atomic models can be advanced using delta/1."
      )
      {:noreply, state}
    else
      new_model = Atomic.delta(state.model, state.input)
      Sx.Event.state_change(state.event_manager, new_model)
      {:noreply, %{state | model: new_model, input: []}}
    end
  end

  def handle_cast({:set_event_manager, event_manager}, state) do
    {:noreply, %{state | event_manager: event_manager}}
  end

  def handle_cast({:set_parent, parent}, state), do: {:noreply, %{state | parent: parent}}

  defp atomic_children(model) do
    Network.children(model)
    |> Enum.flat_map(fn m ->
      case type(m) do
        :atomic -> [m]
        :network -> all_atomics(m)
      end
    end)
  end
end
