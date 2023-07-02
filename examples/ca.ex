defmodule CA do
  @moduledoc """
  The network model for a Cellular Automata simulator.
  """
  defstruct [:cells]

  @doc """
  Create a new CA with `n` cells and using `rule` as the update rule.
  """
  def new(n, rule) when is_integer(n) do
    # initialize with random states
    states = for _k <- 0..n-1, do: :rand.uniform(2) - 1
    new(states, rule)
  end

  def new(states, rule) when is_list(states) do
    # initialize with states
    n = length(states) - 1
    cells = for {s, i} <- Stream.zip(states, 0..n), do: Cell.new(s, i, rule)
    model = %CA{cells: cells |> :array.from_list |> :array.fix}
    Sx.ModelServer.start_link(model)
  end

  def children(%{cells: cells}) do
    :array.to_list(cells)
  end

  def route(%{cells: cells}, _this, _source, {pos, value}) do
    p = if (pos - 1) < 0, do: :array.size(cells) - 1, else: pos - 1
    n = rem(pos + 1, :array.size(cells))
    p_model = :array.get(p, cells)
    n_model = :array.get(n, cells)
    [{p_model, {1, value}},  # to the left neighbor
     {n_model, {-1, value}}] # to the right neighbor
  end
end

defimpl Sx.Model, for: CA do
  def type(_), do: :network
end

defimpl Sx.Network, for: CA do
  def children(network), do: CA.children(network)
  def route(network, this, source, value), do: CA.route(network, this, source, value)
end

defmodule Cell do
  @moduledoc """
  An atomic model of a single cell in a cellular automaton.
  """
  defstruct [:state, :pos, :rule]

  def new(state, pos, rule) do
    {:ok, pid} = Sx.ModelServer.start_link(%Cell{state: state, pos: pos, rule: rule})
    pid
  end

  def delta(%{state: s, rule: rule} = state, input) do
    # Arrange the input & s in a list.
    neighborhood = [{0, s} | input]
    |> List.keysort(0)
    |> Enum.unzip
    |> elem(1)
    %{state | state: rule.(neighborhood)}
  end

  def output(state), do: {state, [{state.pos, state.state}]}
end

defimpl Sx.Model, for: Cell do
  def type(_), do: :atomic
end

defimpl Sx.Atomic, for: Cell do
  def delta(model, input), do: Cell.delta(model, input)
  def output(model), do: Cell.output(model)
end

defmodule CAListener do
  @behaviour Sx.Listener

  def init(ncells) do
    f = File.open!("110.txt", [:write, :delayed_write, :utf8])
    {:ok, %{ncells: ncells, states: [], file: f}}
  end

  def terminate(_, %{file: f}) do
    :ok = File.close(f)
  end

  def output(_source, output, _time, %{states: s, file: f} = state) do
    s = [output|s]
    if length(s) == state.ncells do
      IO.puts(f, s
      |> List.keysort(0)
      |> Enum.unzip
      |> elem(1)
      |> Enum.flat_map(fn x -> if x == 1, do: ['■', ' '], else: ['□', ' '] end)
      |> List.to_charlist)
      {:ok, %{state | states: []}}
    else
      {:ok, %{state | states: s}}
    end
  end

  def state_change(_, _, _, state), do: {:ok, state}
end

defmodule CASimulator do
  def oneten([1, 1, 1]), do: 0
  def oneten([1, 1, 0]), do: 1
  def oneten([1, 0, 1]), do: 1
  def oneten([1, 0, 0]), do: 0
  def oneten([0, 1, 1]), do: 1
  def oneten([0, 1, 0]), do: 1
  def oneten([0, 0, 1]), do: 1
  def oneten([0, 0, 0]), do: 0

  def new(r) do
    {:ok, ca} = CA.new(
      List.duplicate(0, r) ++ [1] ++ List.duplicate(0, r),
      &CASimulator.oneten/1)
    {:ok, sim} = Sx.Simulator.start_link(ca)
    Sx.Simulator.add_listener(sim, CAListener, (r * 2) + 1)
    sim
  end

  def run(_, 0), do: :ok
  def run(sim, n) do
    Sx.Simulator.compute_next_state(sim, [])
    run(sim, n - 1)
  end
end
