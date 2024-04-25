defmodule EnumerableTracer do
  @type label() :: iodata()
  @type t() :: %__MODULE__{enumerable: Enumerable.t(), label: label(), tag: tag()}
  @type tag() :: <<_::64>>

  @typep label_builder() :: {[tag()], ([label()] -> label())}
  @typep state() :: %{caller: tag(), labels: %{tag() => label()}, traces: [trace()]}
  @typep trace() :: {tag(), tag(), label_builder()}

  defstruct [:enumerable, :label, :tag]

  @spec run((-> result)) :: result when result: var
  @spec run(label(), (-> result)) :: result when result: var
  def run(root_label \\ "root", fun) do
    tag = build_tag()
    old_state = put_state(%{caller: tag, labels: %{tag => root_label}, traces: []})

    try do
      result = fun.()

      get_state() |> print()

      result
    after
      put_state(old_state)
    end
  end

  @spec build_tag() :: tag()
  defp build_tag do
    5
    |> :crypto.strong_rand_bytes()
    |> Base.encode32()
  end

  @spec put_state(state()) :: state() | nil
  defp put_state(state), do: Process.put(__MODULE__, state)

  @spec get_state() :: state() | nil
  defp get_state, do: Process.get(__MODULE__)

  @spec print(state()) :: :ok
  defp print(state) do
    %{labels: labels, traces: reversed_traces} = state
    fetch_label = &Map.fetch!(labels, &1)
    traces = Enum.reverse(reversed_traces)

    diagram_lines = compile_diagram(traces, fetch_label)

    render_tabs(diagram: build_diagram(diagram_lines), raw: build_raw(diagram_lines))
  end

  @spec compile_diagram([trace()], (tag() -> label())) :: [iodata()]
  defp compile_diagram(traces, fetch_label) do
    participant_lines =
      traces
      |> Stream.flat_map(fn {from, to, _label_builder} -> [from, to] end)
      |> Stream.uniq()
      |> Stream.map(&["participant ", &1, " as ", fetch_label.(&1)])

    trace_lines =
      Stream.map(traces, fn {from, to, label_builder} ->
        [from, "->>", to, ": " | build_label(label_builder, fetch_label)]
      end)

    indented_lines =
      participant_lines
      |> Stream.concat(trace_lines)
      |> Enum.map(&["  " | &1])

    ["sequenceDiagram" | indented_lines]
  end

  @spec build_label(label_builder(), (tag() -> label())) :: label()
  defp build_label({tags, build}, fetch_label), do: tags |> Enum.map(fetch_label) |> build.()

  @spec build_diagram([iodata()]) :: Kino.Render.t()
  defp build_diagram(lines) do
    lines
    |> Enum.join("\n")
    |> Kino.Mermaid.new()
  end

  @spec build_raw([iodata()]) :: Kino.Render.t()
  defp build_raw(lines) do
    lines
    |> Enum.join("\n    ")
    |> then(&"    ```mermaid\n    #{&1}\n    ```")
    |> Kino.Markdown.new()
  end

  @spec render_tabs(keyword(Kino.Render.t())) :: :ok
  defp render_tabs(tabs) do
    tabs
    |> Kino.Layout.tabs()
    |> Kino.render()

    :ok
  end

  @spec trace(Enumerable.t()) :: t()
  @spec trace(Enumerable.t(), label: iodata()) :: t()
  def trace(enumerable, opts \\ []) do
    tag = build_tag()

    %__MODULE__{
      enumerable: enumerable,
      label: Keyword.get(opts, :label, ["enumerable_", tag]),
      tag: tag
    }
  end

  @doc false
  @spec _trace_count(t()) :: {:ok, non_neg_integer()} | {:error, module()}
  def _trace_count(tracer) do
    register_label(tracer)

    with_caller(tracer.tag, fn caller, callee ->
      put_trace(caller, callee, count_request(tracer))
      result = Enumerable.count(tracer.enumerable)
      put_trace(callee, caller, inspect_response(result))

      with {:error, _module} <- result do
        {:error, Enumerable.EnumerableTracer}
      end
    end)
  end

  @spec count_request(t()) :: label_builder()
  defp count_request(tracer) do
    {[tracer.tag], fn [label] -> ["Enumerable.count(", label, ")"] end}
  end

  @doc false
  @spec _trace_member(t(), term()) :: {:ok, boolean()} | {:error, module()}
  def _trace_member(tracer, element) do
    register_label(tracer)

    with_caller(tracer.tag, fn caller, callee ->
      put_trace(caller, callee, member_request(tracer, element))
      result = Enumerable.member?(tracer.enumerable, element)
      put_trace(callee, caller, inspect_response(result))

      with {:error, _module} <- result do
        {:error, Enumerable.EnumerableTracer}
      end
    end)
  end

  @spec member_request(t(), term()) :: label_builder()
  defp member_request(tracer, element) do
    {[tracer.tag],
     fn [label] -> ["Enumerable.member?(", label, ", ", iodata_inspect(element), ")"] end}
  end

  @doc false
  @spec _trace_reduce(t(), Enumerable.acc(), Enumerable.reducer()) :: Enumerable.result()
  def _trace_reduce(tracer, acc, fun) do
    register_label(tracer)

    {reducer_tag, reducer} = trace_reducer(fun)
    register_label(reducer_tag, ["reducer_", reducer_tag])

    with_caller(tracer.tag, fn caller, callee ->
      put_trace(caller, callee, reduce_request(tracer, acc, reducer_tag))
      continuation = &Enumerable.reduce(tracer.enumerable, &1, reducer)
      reduce(acc, continuation, caller, callee)
    end)
  end

  @spec reduce_request(t(), Enumerable.acc(), tag()) :: label_builder()
  defp reduce_request(tracer, acc, reducer_tag) do
    {[tracer.tag, reducer_tag],
     fn [enumerable, reducer] ->
       ["Enumerable.reduce(", enumerable, ", ", iodata_inspect(acc), ", ", reducer, ")"]
     end}
  end

  @spec trace_reducer(Enumerable.reducer()) :: {tag(), Enumerable.reducer()}
  defp trace_reducer(fun) do
    tag = build_tag()

    reducer =
      fn element, acc ->
        with_caller(tag, fn caller, callee ->
          put_trace(caller, callee, reducer_request(tag, element, acc))
          result = fun.(element, acc)
          put_trace(callee, caller, inspect_response(result))
          result
        end)
      end

    {tag, reducer}
  end

  @spec reducer_request(tag(), term(), term()) :: label_builder()
  defp reducer_request(tag, element, acc) do
    {[tag],
     fn [label] -> [label, ".(", iodata_inspect(element), ", ", iodata_inspect(acc), ")"] end}
  end

  @spec reduce(Enumerable.acc(), Enumerable.continuation(), tag(), tag()) :: Enumerable.result()
  defp reduce(acc, continuation, caller, callee) do
    result = continuation.(acc)
    put_trace(callee, caller, reduce_response(result))

    with {:suspended, new_acc, new_continuation} <- result do
      {:suspended, new_acc, &continue(&1, new_continuation, callee)}
    end
  end

  @spec reduce_response(Enumerable.result()) :: label_builder()
  defp reduce_response(result) do
    case result do
      {status, _acc} when status in [:done, :halted] ->
        inspect_response(result)

      {:suspended, acc, _continuation} ->
        {[], fn [] -> ["{:suspended, ", iodata_inspect(acc), ", continuation}"] end}
    end
  end

  @spec continue(Enumerable.acc(), Enumerable.continuation(), tag()) :: Enumerable.result()
  defp continue(acc, continuation, tag) do
    with_caller(tag, fn caller, callee ->
      put_trace(caller, callee, continue_request(acc))
      reduce(acc, continuation, caller, callee)
    end)
  end

  @spec continue_request(Enumerable.acc()) :: label_builder()
  defp continue_request(acc) do
    {[], fn [] -> ["continuation.(", iodata_inspect(acc), ")"] end}
  end

  @doc false
  @spec _trace_slice(t()) ::
          {:ok, non_neg_integer(), Enumerable.slicing_fun() | Enumerable.to_list_fun()}
          | {:error, module()}
  def _trace_slice(tracer) do
    register_label(tracer)

    with_caller(tracer.tag, fn caller, callee ->
      put_trace(caller, callee, slice_request(tracer))
      result = Enumerable.slice(tracer.enumerable)
      put_trace(callee, caller, slice_response(result))

      case result do
        {:ok, size, slicing_fun} when is_function(slicing_fun, 3) ->
          {:ok, size, trace_slicing_fun(slicing_fun, tracer.tag)}

        {:ok, size, to_list_fun} when is_function(to_list_fun, 1) ->
          {:ok, size, trace_to_list_fun(to_list_fun)}

        {:error, _module} ->
          {:error, Enumerable.EnumerableTracer}
      end
    end)
  end

  @spec slice_request(t()) :: label_builder()
  defp slice_request(tracer) do
    {[tracer.tag], fn [label] -> ["Enumerable.slice(", label, ")"] end}
  end

  @spec slice_response(
          {:ok, size :: non_neg_integer(), Enumerable.slicing_fun() | Enumerable.to_list_fun()}
          | {:error, module()}
        ) :: label_builder()
  defp slice_response(result) do
    case result do
      {:ok, size, slicing_fun} when is_function(slicing_fun, 3) ->
        {[], fn [] -> ["{:ok, ", to_string(size), ", slicing_fun}"] end}

      {:ok, size, to_list_fun} when is_function(to_list_fun, 1) ->
        {[], fn [] -> ["{:ok, ", to_string(size), ", to_list_fun}"] end}

      {:error, _module} ->
        inspect_response(result)
    end
  end

  @spec trace_slicing_fun(Enumerable.slicing_fun(), tag()) :: Enumerable.slicing_fun()
  defp trace_slicing_fun(slicing_fun, tag) do
    fn start, length, step ->
      with_caller(tag, fn caller, callee ->
        put_trace(caller, callee, slicing_fun_request(start, length, step))
        result = slicing_fun.(start, length, step)
        put_trace(caller, callee, inspect_response(result))
        result
      end)
    end
  end

  @spec slicing_fun_request(non_neg_integer(), pos_integer(), pos_integer()) :: label_builder()
  defp slicing_fun_request(start, length, step) do
    {[],
     fn [] ->
       ["slicing_fun.(", to_string(start), ", ", to_string(length), ", ", to_string(step), ")"]
     end}
  end

  @spec trace_to_list_fun(Enumerable.to_list_fun()) :: Enumerable.to_list_fun()
  defp trace_to_list_fun(to_list_fun) do
    fn tracer ->
      with_caller(tracer.tag, fn caller, callee ->
        put_trace(caller, callee, to_list_fun_request(tracer.tag))
        result = to_list_fun.(tracer.enumerable)
        put_trace(callee, caller, inspect_response(result))
        result
      end)
    end
  end

  @spec to_list_fun_request(tag()) :: label_builder()
  defp to_list_fun_request(tag) do
    {[tag], fn [label] -> ["to_list_fun.(", label, ")"] end}
  end

  @spec register_label(t()) :: :ok
  defp register_label(tracer) do
    register_label(tracer.tag, tracer.label)
  end

  @spec register_label(tag(), label()) :: :ok
  defp register_label(tag, label) do
    update_state(fn state ->
      Map.update!(state, :labels, &Map.put(&1, tag, label))
    end)
  end

  @spec with_caller(tag(), (tag(), tag() -> result)) :: result when result: var
  defp with_caller(callee, fun) do
    caller = get_state().caller
    update_state(&Map.put(&1, :caller, callee))

    try do
      fun.(caller, callee)
    after
      update_state(&Map.put(&1, :caller, caller))
    end
  end

  @spec put_trace(tag(), tag(), label_builder()) :: :ok
  defp put_trace(from, to, label_builder) do
    update_state(fn state ->
      Map.update!(state, :traces, &[{from, to, label_builder} | &1])
    end)
  end

  @spec update_state((state() -> state())) :: :ok
  defp update_state(fun) do
    get_state()
    |> fun.()
    |> then(&put_state/1)

    :ok
  end

  @spec inspect_response(any()) :: label_builder()
  defp inspect_response(term) do
    {[], fn [] -> iodata_inspect(term) end}
  end

  @spec iodata_inspect(Inspect.t()) :: iodata()
  defp iodata_inspect(term) do
    opts = Inspect.Opts.new([])

    limit =
      case opts.pretty do
        true -> opts.width
        false -> :infinity
      end

    term
    |> Inspect.Algebra.to_doc(opts)
    |> Inspect.Algebra.group()
    |> Inspect.Algebra.format(limit)
  end

  defimpl Enumerable do
    @impl Enumerable
    def count(tracer) do
      EnumerableTracer._trace_count(tracer)
    end

    @impl Enumerable
    def member?(tracer, element) do
      EnumerableTracer._trace_member(tracer, element)
    end

    @impl Enumerable
    def reduce(tracer, acc, fun) do
      EnumerableTracer._trace_reduce(tracer, acc, fun)
    end

    @impl Enumerable
    def slice(tracer) do
      EnumerableTracer._trace_slice(tracer)
    end
  end
end
