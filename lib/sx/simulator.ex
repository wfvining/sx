defmodule Sx.Simulator do
  @moduledoc """

  This is the core of the simulation engine. It implements a bottom-up
  approach by directly operating on the atomic models contained within
  a network. The core functionality of the simulator is provided by
  two functions. First, `Sx.Simulator.add_listener/3` adds an event
  listener to capture state change and output events from the
  simulation while it is running. Second,
  `Sx.Simulator.compute_next_state/2` advances the simulation to the
  next time step by first computing the output from all atomic and
  network models, then routing input and invoking the
  `Sx.ModelServer.delta/1` function on each atomic model.

  """

  use GenServer

  alias Sx.ModelServer

  @doc """
  Start a simulator for `model`.
  """
  def start_link(model) do
    GenServer.start_link(__MODULE__, model, [])
  end

  @doc """
  Compute the state of the model at the next time.
  """
  def compute_next_state(simulator, input) do
    GenServer.cast(simulator, {:compute_next_state, input})
  end

  @doc """
  Add an event listener.
  """
  @spec add_listener(pid, module, any) :: :ok | {:error, reason :: any}
  def add_listener(simulator, listener, initarg) do
    GenServer.call(simulator, {:add_listener, listener, initarg})
  end

  @doc """
  Stop the simulator.
  """
  @spec stop(pid) :: :ok
  def stop(sim), do: GenServer.cast(sim, :stop)

  @impl true
  def init(model) do
    {:ok, %{model: model,
            atomics: ModelServer.all_atomics(model),
            output: nil,
            event_manager: nil,
            time: 0},
     {:continue, :start_event}}
  end

  @impl true
  def handle_continue(:start_event, state) do
    {:ok, event} = Sx.Event.start_link()
    Enum.each(state.atomics, &ModelServer.set_event_manager(&1, event))
    {:noreply, %{state | event_manager: event}}
  end

  @impl true
  def handle_cast({:compute_next_state, input}, simulator) do
    # compute output, notifying event listeners and routing it between
    # models if `simulator` is a network.
    compute_output(simulator)
    # route the input
    Enum.each(input,
      fn value ->
        case ModelServer.type(simulator.model) do
          :atomic ->
            ModelServer.add_input(simulator.model, value)
          :network ->
            route(simulator.model, simulator.model, value, simulator.event_manager)
        end
      end)
    # tell the event manager that time has advanced
    Sx.Event.tick(simulator.event_manager)
    # advance all the atomic models
    Enum.each(simulator.atomics, &ModelServer.delta/1)
    {:noreply, %{simulator | time: simulator.time + 1}}
  end

  def handle_cast(:stop, state) do
    {:stop, :shutdown, state}
  end

  @impl true
  def handle_call({:add_listener, listener, initarg}, _from, state) do
    {:reply, Sx.Event.add_listener(state.event_manager, listener, initarg), state}
  end

  defp compute_output(%{atomics: atomics} = simulator) do
    atomics
    # get the output from each atomic model and tag it with its source
    |> Enum.map(fn m -> {m, ModelServer.output(m)} end)
    # route output through the parent network.
    |> Enum.each(fn {model, output} ->
      for x <- output do
        route(ModelServer.parent(model), model, x, simulator.event_manager)
      end
    end)
  end

  @impl true
  def terminate(:shutdown, state) do
    Sx.Event.stop(state.event_manager)
  end

  defp route(parent, source, value, event_manager) do
    if parent != source do
      Sx.Event.output(event_manager, source, value)
    end

    if parent == nil do
      # there is nothing to do
      :ok
    else
      # Push the value through the network coupling function(s)
      # transforming the output into inputs for other models within
      # the network
      case ModelServer.route(parent, source, value) do
        {:ok, r} ->
          Enum.each(r, fn {model, value} ->
            if ModelServer.type(model) == :atomic do
              ModelServer.add_input(model, value)
            else
              if parent != model do
                route(model, model, value, event_manager)
              else
                route(ModelServer.parent(parent), model, value, event_manager)
              end
            end
          end)
        {:error, :atomic} ->
          raise RuntimeError # TODO make a better error for this case
      end
    end
  end
end
