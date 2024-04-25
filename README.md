# EnumerableTracer

Builds Mermaid sequence diagrams showing what goes on under the hood for Elixir enumerables.

## Installation

EnumerableTracer is intended to be run in Livebook. It can be installed using [Mix.install/2](https://hexdocs.pm/mix/Mix.html#install/2).

```elixir
Mix.install([{:enumerable_tracer, github: "brettbeatty/elixir_enumerable_tracer"}])
```

## Usage

EnumerableTracer wraps enumerables in a stream that traces their implementation of `Enumerable`. These streams must be run in the function passed to `EnumerableTracer.run/2`, which renders a Mermaid diagram upon completion.

Any easy way to see the underlying enumerable iterated in its entirety is using `Enum.to_list/1`.

```elixir
enumerable = EnumerableTracer.trace(1..3, label: "1..3")

EnumerableTracer.run(fn ->
  Enum.to_list(enumerable)
end)
```

```mermaid
sequenceDiagram
  participant HBSRCQCE as root
  participant G5HOGDJ5 as 1..3
  participant UYY5LA34 as reducer_UYY5LA34
  HBSRCQCE->>G5HOGDJ5: Enumerable.reduce(1..3, {:cont, []}, reducer_UYY5LA34)
  G5HOGDJ5->>UYY5LA34: reducer_UYY5LA34.(1, [])
  UYY5LA34->>G5HOGDJ5: {:cont, [1]}
  G5HOGDJ5->>UYY5LA34: reducer_UYY5LA34.(2, [1])
  UYY5LA34->>G5HOGDJ5: {:cont, [2, 1]}
  G5HOGDJ5->>UYY5LA34: reducer_UYY5LA34.(3, [2, 1])
  UYY5LA34->>G5HOGDJ5: {:cont, [3, 2, 1]}
  G5HOGDJ5->>HBSRCQCE: {:done, [3, 2, 1]}
```

```
[1, 2, 3]
```

For both suspending and halting the enumerable, you can use `Enum.zip/2` to zip the enumerable with another, shorter one.

```elixir
enumerable = EnumerableTracer.trace([:a, :b, :c, :d, :e])

EnumerableTracer.run(fn ->
  Enum.zip(enumerable, 4..7)
end)
```

```mermaid
sequenceDiagram
  participant L7V33XOK as root
  participant NVRGWAGA as enumerable_NVRGWAGA
  participant KTS5HDEU as reducer_KTS5HDEU
  L7V33XOK->>NVRGWAGA: Enumerable.reduce(enumerable_NVRGWAGA, {:cont, []}, reducer_KTS5HDEU)
  NVRGWAGA->>KTS5HDEU: reducer_KTS5HDEU.(:a, [])
  KTS5HDEU->>NVRGWAGA: {:suspend, [:a]}
  NVRGWAGA->>L7V33XOK: {:suspended, [:a], continuation}
  L7V33XOK->>NVRGWAGA: continuation.({:cont, []})
  NVRGWAGA->>KTS5HDEU: reducer_KTS5HDEU.(:b, [])
  KTS5HDEU->>NVRGWAGA: {:suspend, [:b]}
  NVRGWAGA->>L7V33XOK: {:suspended, [:b], continuation}
  L7V33XOK->>NVRGWAGA: continuation.({:cont, []})
  NVRGWAGA->>KTS5HDEU: reducer_KTS5HDEU.(:c, [])
  KTS5HDEU->>NVRGWAGA: {:suspend, [:c]}
  NVRGWAGA->>L7V33XOK: {:suspended, [:c], continuation}
  L7V33XOK->>NVRGWAGA: continuation.({:cont, []})
  NVRGWAGA->>KTS5HDEU: reducer_KTS5HDEU.(:d, [])
  KTS5HDEU->>NVRGWAGA: {:suspend, [:d]}
  NVRGWAGA->>L7V33XOK: {:suspended, [:d], continuation}
  L7V33XOK->>NVRGWAGA: continuation.({:cont, []})
  NVRGWAGA->>KTS5HDEU: reducer_KTS5HDEU.(:e, [])
  KTS5HDEU->>NVRGWAGA: {:suspend, [:e]}
  NVRGWAGA->>L7V33XOK: {:suspended, [:e], continuation}
  L7V33XOK->>NVRGWAGA: continuation.({:halt, []})
  NVRGWAGA->>L7V33XOK: {:halted, []}
```

```
[a: 4, b: 5, c: 6, d: 7]
```

## Shortcomings

This is still very much in a hacked-together state.

It doesn't do anything to escape values rendered in Mermaid, so any inspected values with special characters for Mermaid could break the diagram. For example, any values that inspect with a "#" prefix will get cut off.

Also the names of reducers cannot be altered.
