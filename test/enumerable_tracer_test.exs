defmodule EnumerableTracerTest do
  use ExUnit.Case
  doctest EnumerableTracer

  test "greets the world" do
    assert EnumerableTracer.hello() == :world
  end
end
