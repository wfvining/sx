defmodule Xor do
  @moduledoc """
  Exclusive Or atomic model.
  """
  defstruct state: false

  def new(), do: %__MODULE__{}

  def delta(_state, input) do
    {:x1, x1} = List.keyfind!(input, :x1, 0)
    {:x2, x2} = List.keyfind!(input, :x2, 0)
    %__MODULE__{state: (x1 and (not x2)) or ((not x1) and x2)}
  end

  def output(state), do: state.state
end

defimpl Sx.Model, for: Xor do
  def type(_), do: :atomic
end

defimpl Sx.Atomic, for: Xor do
  def delta(m, input), do: Xor.delta(m, input)
  def output(m), do: {m, [{:xor, Xor.output(m)}]}
end

defmodule Memory do
  @moduledoc """
  1-bit Memory model
  """

  defstruct s0: false, s1: false

  def new(), do: %__MODULE__{}

  def delta(%{s1: s1}, [value]), do: %__MODULE__{s0: s1, s1: value}

  def output(%{s0: s0} = m), do: {m, [{:m, s0}]}
end

defimpl Sx.Model, for: Memory do
  def type(_), do: :atomic
end

defimpl Sx.Atomic, for: Memory do
  def delta(m, input), do: Memory.delta(m, input)
  def output(m), do: Memory.output(m)
end

defmodule N1 do
  @moduledoc """
  Top level network.
  """

  defstruct [:n2, :m]

  def new(n2, m) do
    # Can't set the paren't yet because we aren't in ther ModelServer
    # process.
    %__MODULE__{n2: n2, m: m}
  end

  def route(%{n2: n2, m: m}, source, value) do
     # This is weird - we are assuming that route is always called by
     # the model server for this model. Seems like a reasonable
     # assumption, but using self() here feels very wrong. - maybe the
     # pid should be passed in.
    cond do
      source == self() ->
        # input to the network gets routed to n2
        [{n2, value}]
      source == n2 ->
        # output from n2 becomes input to m & output fron the network
        [{self(), value}, {m, value}]
      source == m ->
        # output from m routes to n2
        [{n2, value}]
    end
  end
end

defimpl Sx.Model, for: N1 do
  def type(_), do: :network
end

defimpl Sx.Network, for: N1 do
  def children(%{n2: n2, m: m}), do: [n2, m]

  def all_atomics(%{n2: n2, m: m}) do
    List.flatten([m, Sx.ModelServer.all_atomics(n2)])
  end

  def route(n, source, value), do: N1.route(n, source, value)
end

defmodule N2 do
  @moduledoc """
  The inner network that performs the two xor operations.
  """

  defstruct [:o1, :o2]

  def new(o1, o2), do: %__MODULE__{o1: o1, o2: o2}

  def route(%{o1: o1, o2: o2}, source, {tag, value}) do
    cond do
      source == self() ->
        if tag == :m do
          [{o2, {:x2, value}}]
        else
          [{o1, {tag, value}}]
        end
      source == o1 ->
        # route as input to o2
        [{o2, {:x1, value}}]
      source == o2 ->
        # output from o2 routes to output from the network
        [{self(), value}]
    end
  end
end

defimpl Sx.Model, for: N2 do
  def type(_), do: :network
end

defimpl Sx.Network, for: N2 do
  def children(%{o1: o1, o2: o2}), do: [o1, o2]

  def all_atomics(m) do
    [m.o1, m.o2]
  end

  def route(n, source, value), do: N2.route(n, source, value)
end

defmodule LogicListener do
  @behaviour Sx.Listener

  def init(top), do: {:ok, top}

  def terminate(_, _), do: :ok

  def output(source, output, time, top) do
    if source == top do
      IO.write("#{if output, do: "1", else: "0"} ")
    end
    {:ok, top}
  end

  def state_change(_, _, _, state), do: {:ok, state}
end

defmodule Sim do
  alias String.Chars.Time
  alias Sx.Simulator
  alias Sx.ModelServer
  def new() do
    {:ok, _} = Sx.Event.start_link()
    {:ok, o1} = ModelServer.start_link(Xor.new())
    {:ok, o2} = ModelServer.start_link(Xor.new())
    {:ok, m} = ModelServer.start_link(Memory.new())
    n2_model = N2.new(o1, o2)
    {:ok, n2} = ModelServer.start_link(n2_model)
    {:ok, n1} = ModelServer.start_link(N1.new(n2, m))
    {:ok, sim} = Sx.Simulator.start_link(n1)
    Sx.Simulator.add_listener(sim, LogicListener, n1)
    sim
  end

  @doc """
  Run the simulation feeding it the trajectoty `input`.
  """
  def run(sim) do
    run(sim, 0, 0)
  end

  defp run(sim, cycle, clock) do
    with {:ok, x1} <- read_bool("\nx₁"),
         {:ok, x2} <- read_bool("x₂") do
      IO.write(
        "xx M#{cycle} C#{clock}\t"
        <> "#{if x1, do: "1", else: "0"} "
        <> "#{if x2, do: "1", else: "0"} "
        <> "\tyy M#{cycle + 1} C#{clock}-#{clock + 3}\t")
      run_cycle(sim, [{:x1, x1}, {:x2, x2}], 0)
      # sleep so the ouput print can happen befor the new-line in the
      # x1 prompt
      :timer.sleep(100)
      run(sim, cycle+1, clock+3)
    end
  end

  defp read_bool(prompt) do
    case IO.gets("#{prompt} > ") do
      :eof -> :eof
      str ->
        if String.starts_with?(str, "q") do
          :quit
        else
          {:ok, String.starts_with?(str, "1")}
        end
    end
  end

  defp run_cycle(_, _, 3), do: :ok
  defp run_cycle(sim, input, clock) do
    Sx.Simulator.compute_next_state(sim, input)
    run_cycle(sim, input, clock+1)
  end
end
