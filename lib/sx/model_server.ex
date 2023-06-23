defmodule Sx.ModelServer do
  @moduledoc """
  The model server manages the state of a single model.
  """

  use GenServer

  require Logger

  alias Sx.ModelServer
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
  def all_atomics(server), do: GenServer.call(server, :all_atomics)

  def add_input(server, input), do: GenServer.cast(server, {:add_input, input})

  def delta(server), do: GenServer.cast(server, :delta)

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

  @impl true
  def init(model) do
    if Model.type(model) == :network do
      Enum.each(Network.children(model), &set_parent(&1, self()))
    end
    {:ok, %{model: model, input: [], parent: nil}}
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
      r = Network.route(state.model, source, value)
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
      Sx.Event.state_change(new_model)
      {:noreply, %{state | model: new_model, input: []}}
    end
  end

  def handle_cast({:set_parent, parent}, state), do: {:noreply, %{state | parent: parent}}

  defp atomic_children(model) do
    Network.children(model)
    |> Enum.flat_map(fn m ->
      case ModelServer.type(m) do
        :atomic -> [m]
        :network -> all_atomics(m)
      end
    end)
  end
end
