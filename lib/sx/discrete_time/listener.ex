defmodule Sx.DiscreteTime.Listener do
  @moduledoc """
  Simulation event listener.
  """

  # init(any) :: listener_state
  @callback init(initarg :: any) :: {:ok, state :: any} | {:error, reason :: any}
  # terminate(listener_state)
  @callback terminate(reason :: any, state :: any) :: :ok
  # state_change(model, model_state, time, listener_state)
  @callback state_change(model :: pid, model_state :: Sx.Model.t, time :: integer, state :: any) :: {:ok, any} | {:error, reason :: any}
  # output(source, output, time, listener_state)
  @callback output(source :: pid, output :: any, time :: integer, state :: any) :: {:ok, any} | {:error, reason :: any}
end
