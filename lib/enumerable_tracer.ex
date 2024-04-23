defmodule EnumerableTracer do
  def trace(enumerable) do
    fn cmd_acc, reducer ->
      traced_reducer = fn element, {traces, acc} ->
        {new_cmd, new_acc} = reducer.(element, acc)

        call_trace =
          {"enumerable", "reducer", ["reducer.(", inspect(element), ", ", inspect(acc), ")"]}

        result_trace = {"reducer", "enumerable", inspect({new_cmd, new_acc})}
        {new_cmd, {[result_trace, call_trace | traces], new_acc}}
      end

      continuation = &Enumerable.reduce(enumerable, &1, traced_reducer)
      continue(cmd_acc, continuation, _traces = [], _counter = 0)
    end
  end

  defp continue(cmd_acc, continuation, traces, counter) do
    call_label =
      if counter > 0 do
        ["continuation", to_string(counter), ".(", inspect(cmd_acc), ")"]
      else
        ["Enumerable.reduce(enumerable, ", inspect(cmd_acc), ", reducer)"]
      end

    call_trace = {"caller", "enumerable", call_label}
    {cmd, acc} = cmd_acc

    case continuation.({cmd, {[call_trace | traces], acc}}) do
      {result_type, {new_traces, new_acc}} when result_type in [:done, :halted] ->
        result = {result_type, new_acc}
        result_trace = {"enumerable", "caller", inspect(result)}
        print_trace([result_trace | new_traces])
        result

      {:suspended, {new_traces, new_acc}, new_continuation} ->
        result_label = [
          "{:suspended, ",
          inspect(new_acc),
          ", continuation",
          to_string(counter + 1),
          "}"
        ]

        result_trace = {"enumerable", "caller", result_label}
        newer_traces = [result_trace | new_traces]
        {:suspended, new_acc, &continue(&1, new_continuation, newer_traces, counter + 1)}
    end
  end

  defp print_trace(traces) do
    traces
    |> build_diagram([])
    |> to_string()
    |> Kino.Mermaid.new()
    |> Kino.render()
  end

  defp build_diagram(traces, acc)

  defp build_diagram([trace | traces], acc) do
    {from, to, label} = trace
    build_diagram(traces, ["\n ", from, "->>", to, ": ", label | acc])
  end

  defp build_diagram([], acc) do
    ["sequenceDiagram" | acc]
  end
end
