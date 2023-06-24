defprotocol Sx.Network do
  @moduledoc """
  This protocol must be implemented by every network model.
  """

  @doc """
  Route a value through the network, applying coupling functions and
  returning inputs to subordinate models.

  The items in the returned list are tuples where the first element is
  the pid of the model server where the value should be sent as input
  (or output). To produce output from the network, the pid should be
  equal to the the pid of the network's model server
  (i.e. `thisnetwork`).
  """
  @spec route(t, pid, pid, any) :: [{pid, any}]
  def route(network, thisnetwork, source, value)

  @doc """
  Rerturn the immediate children of the model.
  """
  @spec children(t) :: [pid]
  def children(network)
end
