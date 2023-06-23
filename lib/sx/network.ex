defprotocol Sx.Network do
  @moduledoc """
  This protocol must be implemented by every network model.
  """

  @doc """
  Return all the atomic models within this network and any networks it
  contains.
  """
  @spec all_atomics(network :: Sx.Network.t) :: [pid]
  def all_atomics(network)

  @doc """
  Route a value through the network, applying coupling functions and
  returning inputs to subordinate models.
  """
  @spec route(t, pid, any) :: [{pid, any}]
  def route(network, source, value)

  @doc """
  Rerturn the immediate children of the model.
  """
  @spec children(t) :: [pid]
  def children(network)
end
