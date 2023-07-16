defprotocol Sx.DiscreteTime.Model do
  @moduledoc """
  This protocol must be implemented by every Network and Atomic model
  used with the simulation engine.
  """

  @doc """
  Return the type of the model, `:atomic` or `:network`
  """
  @spec type(t) :: :atomic | :network
  def type(m)
end
