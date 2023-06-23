defprotocol Sx.Atomic do
  @moduledoc """
  This protocol must be implemented by atomic models used with the
  simulator.
  """

  @doc """
  Advance the state of the model.
  """
  @spec delta(t, [any]) :: t
  def delta(model, input)

  @doc """
  Compute the model output.
  """
  @spec output(t) :: any
  def output(model)
end
