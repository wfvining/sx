defmodule Sx.Event do
  @moduledoc """
  And event manager for simulation-related events.
  """

  require Logger

  use GenServer

  def start_link(), do: GenServer.start_link(__MODULE__, nil)

  @doc """
  Notify the event manager that time has advanced.
  """
  def tick(event), do: GenServer.cast(event, :tick)

  @doc """
  Notify the event manager that a model has changed state.
  """
  @spec state_change(pid, any) :: :ok
  def state_change(event, new_state) do
    GenServer.cast(event, {:state_change, self(), new_state})
  end

  @doc """
  Notify the event manager that a model has produced output.
  """
  def output(event, source, output) do
    GenServer.cast(event, {:output, source, output})
  end

  @doc """
  Add an event listener.
  """
  @spec add_listener(pid, module, any) :: :ok | {:error, reason :: any}
  def add_listener(event, listener, initarg) do
    GenServer.call(event, {:add_listener, listener, initarg})
  end

  @doc """
  Stop the event manager.
  """
  def stop(event), do: GenServer.cast(event, :stop)

  @impl true
  def init(nil), do: {:ok, %{listeners: [], time: 0}}

  @impl true
  def handle_cast(:tick, state), do: {:noreply, %{state | time: state.time + 1}}

  def handle_cast({:state_change, model, model_state}, state) do
    listeners = notify_state(model, model_state, state.time, state.listeners)
    {:noreply, %{state | listeners: listeners}}
  end

  def handle_cast({:output, source, output}, state) do
    listeners = notify_output(source, output, state.time, state.listeners)
    {:noreply, %{state | listeners: listeners}}
  end

  def handle_cast(:stop, state) do
    {:stop, :normal, state}
  end

  defp notify_output(source, output, time, listeners) do
    do_notify(:output, source, output, time, listeners)
  end

  defp notify_state(model, data, time, listeners) do
    do_notify(:state_change, model, data, time, listeners)
  end

  defp do_notify(_notification, _model, _data, _time, []), do: []
  defp do_notify(notification, model, data, time, [{l, state}|rest]) do
    case apply(l, notification, [model, data, time, state]) do
      {:ok, state} ->
        [{l, state} | do_notify(notification, model, data, time, rest)]
      {:error, reason} ->
        Logger.error("Event listener failed with reason #{reason} - removing it")
        l.terminate(reason, state)
        do_notify(notification, model, data, time, rest)
    end
  end

  @impl true
  def handle_call({:add_listener, listener, initarg}, _from, eventstate) do
    case listener.init(initarg) do
      {:ok, state} ->
        {:reply, :ok, %{eventstate | listeners: [{listener, state} | eventstate.listeners]}}
      {:error, _reason} = error ->
        {:reply, error, eventstate}
    end
  end

  @impl true
  def terminate(:normal, state) do
    Enum.each(
      state.listeners,
      fn {l, lstate} -> l.terminate(:normal, lstate) end)
  end
end
