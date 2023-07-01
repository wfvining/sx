# Sx

Simulation engines based on *Building Software for Simulation* by James Nutaro.

## Installation

No good installation mechanism right now - just load the modules.

## Usage

There are a number of protocols that need to be implemented for each
model, depending on its type (`Sx.Model`, `Sx.Network`, `Sx.Atomic`)
then the top-level network can be passed to `Sx.Simulator.start_link/1`
and advanced through time with `Sx.Simulator.compute_next_state/2`.

The logic-machine example from the book is implemented in
`examples/logic.ex`

A cellular automata example is implemented in `examples/ca.ex`.

```
$ iex -S mix
iex(1)> c("examples/logic.ex")

[LogicListener, Memory, N1, N2, Sim, Sx.Atomic.Memory, Sx.Atomic.Xor,
 Sx.Model.Memory, Sx.Model.N1, Sx.Model.N2, Sx.Model.Xor, Sx.Network.N1,
 Sx.Network.N2, Xor]
iex(2)> s = Sim.new()
#PID<0.23839.3>
iex(3)> Sim.run(s)

x₁ > 1
x₂ > 0
xx M0 C0        1 0     yy M1 C0-3      0 0 1
x₁ > 1
x₂ > 0
xx M1 C3        1 0     yy M2 C3-6      1 1 0
x₁ > 1
x₂ > 0
xx M2 C6        1 0     yy M3 C6-9      0 0 1
x₁ > 1
x₂ > 0
xx M3 C9        1 0     yy M4 C9-12     1 1 0
x₁ > 1
x₂ > 0
xx M4 C12       1 0     yy M5 C12-15    0 0 1
x₁ > 1
x₂ > 0
xx M5 C15       1 0     yy M6 C15-18    1 1 0
x₁ > 1
x₂ > 0
xx M6 C18       1 0     yy M7 C18-21    0 0 1
x₁ > 0
x₂ > 0
xx M7 C21       0 0     yy M8 C21-24    1 1 1
x₁ > 0
x₂ > 0
xx M8 C24       0 0     yy M9 C24-27    1 1 1
x₁ > 1
x₂ > 0
xx M9 C27       1 0     yy M10 C27-30   1 1 0
x₁ > 1
x₂ > 0
xx M10 C30      1 0     yy M11 C30-33   0 0 1
x₁ > 1
x₂ > 0
xx M11 C33      1 0     yy M12 C33-36   1 1 0
x₁ > 0
x₂ > 0
xx M12 C36      0 0     yy M13 C36-39   0 0 0
x₁ > 0
x₂ > 0
xx M13 C39      0 0     yy M14 C39-42   0 0 0
x₁ > q
:quit
iex(4)>
```
