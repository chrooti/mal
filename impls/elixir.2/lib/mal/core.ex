defmodule Mal.Core do
  alias Mal.Env
  alias Mal.EvalError
  alias Mal.ExceptionWrapperError
  alias Mal.Printer
  alias Mal.Reader
  alias Mal.Type
  alias Mal.Type.Function

  @seq_types [:list, :vector]
  @collection_types [:list, :vector, :map]

  @spec ns() :: %{String.t() => Type.t()}
  def ns do
    %{
      "+" => fn
        [a, b], env when is_integer(a) and is_integer(b) -> {a + b, env}
        args, env -> argserr("+ expects two integers arguments", args, env)
      end,
      "-" => fn
        [a, b], env when is_integer(a) and is_integer(b) -> {a - b, env}
        args, env -> argserr("- expects two integers arguments", args, env)
      end,
      "*" => fn
        [a, b], env when is_integer(a) and is_integer(b) -> {a * b, env}
        args, env -> argserr("* expects two integers arguments", args, env)
      end,
      "/" => fn
        [a, b], env when is_integer(a) and is_integer(b) -> {Integer.floor_div(a, b), env}
        args, env -> argserr("/ expects two integers arguments", args, env)
      end,
      "pr-str" => fn args, env -> {prn(args, " ", env), env} end,
      "str" => fn args, env -> {prn(args, "", env, _print_readably = false), env} end,
      "prn" => fn args, env ->
        args
        |> prn(" ", env)
        |> IO.puts()

        {nil, env}
      end,
      "println" => fn args, env ->
        args
        |> prn(" ", env, _print_readably = false)
        |> IO.puts()

        {nil, env}
      end,
      "list" => fn args, env -> {make_list(args), env} end,
      "list?" => fn
        [{:list, _values, _meta}], env -> {true, env}
        [_arg], env -> {false, env}
        args, env -> argserr("list? expects a single argument", args, env)
      end,
      "empty?" => fn
        [{type, values, _meta}], env when type in @seq_types -> {values == [], env}
        args, env -> argserr("empty? expects a single list or vector argument", args, env)
      end,
      "count" => fn
        [{type, values, _meta}], env when type in @seq_types -> {length(values), env}
        [nil], env -> {0, env}
        args, env -> argserr("count expects a single list, vector or nil argument", args, env)
      end,
      "=" => fn
        [a, b], env ->
          {unwrap_vector_recursive(a) == unwrap_vector_recursive(b), env}

        args, env ->
          argserr("= expects two arguments", args, env)
      end,
      "<" => fn
        [a, b], env when is_integer(a) and is_integer(b) -> {a < b, env}
        args, env -> argserr("< expects two integer arguments", args, env)
      end,
      "<=" => fn
        [a, b], env when is_integer(a) and is_integer(b) -> {a <= b, env}
        args, env -> argserr("<= expects two integer arguments", args, env)
      end,
      ">" => fn
        [a, b], env when is_integer(a) and is_integer(b) -> {a > b, env}
        args, env -> argserr("> expects two integer arguments", args, env)
      end,
      ">=" => fn
        [a, b], env when is_integer(a) and is_integer(b) -> {a >= b, env}
        args, env -> argserr(">= expects two integer arguments", args, env)
      end,
      "read-string" => fn
        [str], env when is_binary(str) -> {Reader.read_str(str), env}
        args, env -> argserr("read-string expects a single string argument", args, env)
      end,
      "slurp" => fn
        [filename], env when is_binary(filename) -> {File.read!(filename), env}
        args, env -> argserr("slurp expects a single string argument", args, env)
      end,
      "atom" => fn
        [value], env ->
          {instance_id, atom_id, env} = Env.make_atom(env, value)
          {{:atom, instance_id, atom_id}, env}

        args, env ->
          argserr("atom expects a single argument", args, env)
      end,
      "atom?" => fn
        [{:atom, _instance_id, _atom_id}], env -> {true, env}
        [_value], env -> {false, env}
        args, env -> argserr("atom? expects a single argument", args, env)
      end,
      "deref" => fn
        [{:atom, instance_id, atom_id}], env -> {Env.get_atom(env, instance_id, atom_id), env}
        args, env -> argserr("deref expects a single argument", args, env)
      end,
      "reset!" => fn
        [{:atom, instance_id, atom_id}, value], env ->
          {value, Env.set_atom(env, instance_id, atom_id, value)}

        args, env ->
          argserr("reset! expects two arguments: an atom and a value", args, env)
      end,
      "swap!" => fn
        [{:atom, instance_id, atom_id}, func = %Function{} | args], env ->
          old_value = Env.get_atom(env, instance_id, atom_id)
          {value, new_env} = func.builtin.([old_value | args], env)

          {value,
           Env.set_atom(
             %{new_env | curr_instance_id: env.curr_instance_id},
             instance_id,
             atom_id,
             value
           )}

        args, env ->
          argserr("swap! expects at least two arguments: an atom and a function", args, env)
      end,
      "cons" => fn
        [value, {type, values, _meta}], env when type in @seq_types ->
          {make_list([value | values]), env}

        args, env ->
          argserr("cons expects two arguments: a value and a list or a vector", args, env)
      end,
      "concat" => fn seqs, env ->
        result =
          seqs
          |> Enum.map(fn
            {type, values, _meta} when type in @seq_types -> values
            arg -> argerr("seqs arguments must be either lists or vectors", arg, env)
          end)
          |> Enum.concat()

        {make_list(result), env}
      end,
      "quasiquote" => fn
        [ast], env -> {quasiquote(ast), env}
        args, env -> argserr("quasiquote expects a single argument", args, env)
      end,
      "vec" => fn
        [{type, values, _meta}], env when type in @seq_types -> {make_vector(values), env}
        args, env -> argserr("vec expects a single list or vector argument", args, env)
      end,
      "nth" => fn
        [{type, values, _meta}, idx], env when type in @seq_types and idx >= 0 ->
          {nth(values, idx), env}

        args, env ->
          argserr("nth expects a single list or vector argument", args, env)
      end,
      "first" => fn
        [{type, values, _meta}], env when type in @seq_types ->
          {List.first(values), env}

        [nil], env ->
          {nil, env}

        args, env ->
          argserr("first expects a single list or vector argument", args, env)
      end,
      "rest" => fn
        [{type, values, _meta}], env when type in @seq_types ->
          {values |> rest() |> make_list(), env}

        [nil], env ->
          {make_list([]), env}

        args, env ->
          argserr("rest expects a single list or vector argument", args, env)
      end,
      "macro?" => fn
        [%Function{} = func], env -> {func.is_macro, env}
        [_value], env -> {false, env}
        args, env -> argserr("macro? expects a single argument", args, env)
      end,
      "throw" => &mal_throw/2,
      "apply" => fn
        [func = %Function{} | args = [_ | _]], env ->
          case List.pop_at(args, -1) do
            {{type, values, _meta}, args} when type in @seq_types ->
              {result, new_env} = func.builtin.(args ++ values, env)
              {result, %{new_env | curr_instance_id: env.curr_instance_id}}

            {last_arg, _args} ->
              argerr("apply expects a list as last argument", last_arg, env)
          end

        args, env ->
          argserr("apply expects at least a function and a list argument", args, env)
      end,
      "map" => fn
        [func = %Function{}, {type, values, _meta}], env when type in @seq_types ->
          mal_map(func, values, env)

        args, env ->
          argserr("map expects a function and a list argument", args, env)
      end,
      "nil?" => fn
        [arg], env -> {arg == nil, env}
        args, env -> argserr("nil? expects a single argument", args, env)
      end,
      "true?" => fn
        [arg], env -> {arg == true, env}
        args, env -> argserr("true? expects a single argument", args, env)
      end,
      "false?" => fn
        [arg], env -> {arg == false, env}
        args, env -> argserr("false? expects a single argument", args, env)
      end,
      "symbol?" => fn
        [{:symbol, _}], env -> {true, env}
        [_arg], env -> {false, env}
        args, env -> argserr("false? expects a single argument", args, env)
      end,
      "symbol" => fn
        [name], env when is_binary(name) -> {{:symbol, name}, env}
        args, env -> argserr("symbol expects a single string argument", args, env)
      end,
      "keyword" => fn
        [name], env when is_binary(name) -> {String.to_atom(name), env}
        [name], env when is_atom(name) -> {name, env}
        args, env -> argserr("keyword expects a single string argument", args, env)
      end,
      "keyword?" => fn
        [name], env -> {is_atom(name), env}
        args, env -> argserr("keyword? expects a single argument", args, env)
      end,
      "vector" => fn args, env -> {make_vector(args), env} end,
      "vector?" => fn
        [{:vector, _values, _meta}], env -> {true, env}
        [_arg], env -> {false, env}
        args, env -> argserr("vector? expects a single argument", args, env)
      end,
      "sequential?" => fn
        [{type, _values, _meta}], env when type in @seq_types -> {true, env}
        [_arg], env -> {false, env}
        args, env -> argserr("sequential? expects a single argument", args, env)
      end,
      "hash-map" => fn args, env ->
        case merge(%{}, args) do
          {:ok, pairs} -> {make_map(pairs), env}
          :error -> raise EvalError, message: "hash-map must have an even number of arguments"
        end
      end,
      "map?" => fn
        [{:map, _pairs, _meta}], env -> {true, env}
        [_arg], env -> {false, env}
        args, env -> argserr("map? expects a single argument", args, env)
      end,
      "assoc" => fn
        [{:map, old_pairs, _meta} | args], env ->
          case merge(old_pairs, args) do
            {:ok, pairs} -> {make_map(pairs), env}
            :error -> raise EvalError, message: "assoc must have an even number of arguments"
          end

        args, env ->
          argserr("assoc expects a map as first argument", args, env)
      end,
      "dissoc" => fn
        [{:map, pairs, _meta} | keys], env ->
          {pairs |> Map.drop(keys) |> make_map(), env}

        args, env ->
          argserr("dissoc expects a map as first argument", args, env)
      end,
      "get" => fn
        [{:map, pairs, _meta}, key], env -> {Map.get(pairs, key), env}
        [nil, _key], env -> {nil, env}
        args, env -> argserr("get expects a map or nil and a key argument", args, env)
      end,
      "contains?" => fn
        [{:map, pairs, _meta}, key], env -> {Map.has_key?(pairs, key), env}
        args, env -> argserr("contains? expects a map and a key argument", args, env)
      end,
      "keys" => fn
        [{:map, pairs, _meta}], env -> {pairs |> Map.keys() |> make_list(), env}
        args, env -> argserr("keys expects a map argument", args, env)
      end,
      "vals" => fn
        [{:map, pairs, _meta}], env -> {pairs |> Map.values() |> make_list(), env}
        args, env -> argserr("vals expects a map argument", args, env)
      end,
      "readline" => fn
        [prompt], env when is_binary(prompt) ->
          case IO.gets(prompt) do
            :eof -> {nil, env}
            {:error, reason} -> raise reason
            input -> {String.trim_trailing(input, "\n"), env}
          end

        args, env ->
          argserr("readline expects a string argument", args, env)
      end,
      "time-ms" => fn
        [], env -> {System.os_time(), env}
        args, env -> argserr("time-ms expects no argument", args, env)
      end,
      "meta" => fn
        [{type, _values, meta}], env when type in @collection_types ->
          {meta, env}

        [%Function{} = func], env ->
          {func.meta, env}

        args, env ->
          argserr("meta expects a single list, vector, map or function argument", args, env)
      end,
      "with-meta" => fn
        [{type, values, _old_meta}, new_meta], env when type in @collection_types ->
          {{type, values, new_meta}, env}

        [%Function{} = func, new_meta], env ->
          {%{func | meta: new_meta}, env}

        args, env ->
          argserr(
            "with-meta expects a list, vector, map or function and a value argument",
            args,
            env
          )
      end,
      "fn?" => fn
        [%Function{} = func], env -> {not func.is_macro, env}
        [_arg], env -> {false, env}
        args, env -> argserr("string? expects a single argument", args, env)
      end,
      "string?" => fn
        [string], env -> {is_binary(string), env}
        args, env -> argserr("string? expects a single argument", args, env)
      end,
      "number?" => fn
        [integer], env -> {is_integer(integer), env}
        args, env -> argserr("number? expects a single argument", args, env)
      end,
      "seq" => fn
        [list = {:list, values, _meta}], env ->
          {if(values == [], do: nil, else: list), env}

        [{:vector, values, _meta}], env ->
          {if(values == [], do: nil, else: make_list(values)), env}

        [string], env when is_binary(string) ->
          {if(string == "", do: nil, else: string |> String.codepoints() |> make_list()), env}

        [nil], env ->
          {nil, env}

        args, env ->
          argserr("seq expects a single list, vector or string argument", args, env)
      end,
      "conj" => fn
        [{:list, old_values, _meta} | args], env ->
          new_list =
            args
            |> Enum.reduce(old_values, fn arg, values -> [arg | values] end)
            |> make_list()

          {new_list, env}

        [{:vector, vector, _meta} | values], env ->
          {make_vector(vector ++ values), env}

        args, env ->
          argserr("conj takes at least a list or vector argument", args, env)
      end
    }
    |> Map.new(fn
      {name, builtin} when is_function(builtin, 2) -> {name, %Function{builtin: builtin}}
    end)
  end

  @spec argerr(String.t(), Type.t(), Env.t()) :: no_return()
  defp argerr(msg, arg, env) do
    msg = msg <> ", got " <> Printer.pr_str(arg, env)

    raise EvalError, message: msg
  end

  @spec argserr(String.t(), [Type.t()], Env.t()) :: no_return()
  defp argserr(msg, args, env) do
    msg = msg <> ", got " <> prn(args, ", ", env)

    raise EvalError, message: msg
  end

  @spec prn([Type.t()], String.t(), Env.t(), boolean()) :: String.t()
  def prn(args, sep, env, print_readably \\ true),
    do: Enum.map_join(args, sep, &Printer.pr_str(&1, env, print_readably))

  @spec unwrap_vector_recursive(Type.vector()) :: [Type.t()]
  @spec unwrap_vector_recursive(Type.mal_list()) :: [Type.t()]
  @spec unwrap_vector_recursive(Type.mal_map()) :: %{Type.t() => Type.t()}
  @spec unwrap_vector_recursive(t) :: t when t: Type.t()

  defp unwrap_vector_recursive({:vector, values, _meta}),
    do: Enum.map(values, &unwrap_vector_recursive/1)

  defp unwrap_vector_recursive({:list, values, _meta}),
    do: Enum.map(values, &unwrap_vector_recursive/1)

  defp unwrap_vector_recursive({:map, pairs, _meta}),
    do: Map.new(pairs, fn {key, value} -> {key, unwrap_vector_recursive(value)} end)

  defp unwrap_vector_recursive(value), do: value

  @spec quasiquote(Type.t()) :: Type.t()
  def quasiquote({:vector, values, _meta}),
    do: make_list([{:symbol, "vec"}, do_quasiquote(values)])

  def quasiquote({:list, values, _meta}) do
    case values do
      [{:symbol, "unquote"}, ast] ->
        ast

      [{:symbol, "unquote"}, _ast | _rest] ->
        raise EvalError, message: "quasiquote expects a single argument after unquote"

      _ ->
        do_quasiquote(values)
    end
  end

  def quasiquote(map = {:map, _, _}),
    do: make_list([{:symbol, "quote"}, map])

  def quasiquote(symbol = {:symbol, _}),
    do: make_list([{:symbol, "quote"}, symbol])

  def quasiquote(ast), do: ast

  @spec do_quasiquote([Type.t()]) :: Type.mal_list()
  defp do_quasiquote([{:list, [{:symbol, "splice-unquote"} | ast], _meta} | rest]) do
    case ast do
      [ast] ->
        make_list([{:symbol, "concat"}, ast, do_quasiquote(rest)])

      _ ->
        raise EvalError, message: "quasiquote expects a single argument after splice-unquote"
    end
  end

  defp do_quasiquote([ast | rest]) do
    make_list([{:symbol, "cons"}, quasiquote(ast), do_quasiquote(rest)])
  end

  defp do_quasiquote([]), do: make_list([])

  @spec nth([t], integer()) :: t when t: var
  defp nth([value | _rest], 0), do: value
  defp nth([_value | rest], n), do: nth(rest, n - 1)

  defp nth(_list, _n) do
    raise EvalError, message: "nth index out of range"
  end

  @spec rest(list()) :: list()
  defp rest([_value | rest]), do: rest
  defp rest([]), do: []

  @spec mal_throw([Type.t()], Env.t()) :: no_return()
  defp mal_throw([value], env) do
    raise ExceptionWrapperError, value: value, env: env
  end

  defp mal_throw(args, env) do
    argserr("throw expectes a single argument", args, env)
  end

  @spec mal_map(Function.t(), [Type.t()], Env.t()) :: {Type.mal_list(), Env.t()}
  defp mal_map(func, args, env) do
    {values, env} =
      Enum.reduce(args, {[], env}, fn value, {args, env} ->
        {result, new_env} = func.builtin.([value], env)
        {[result | args], %{new_env | curr_instance_id: env.curr_instance_id}}
      end)

    {values |> Enum.reverse() |> make_list(), env}
  end

  @spec merge(map(), [Type.t()]) :: {:ok, %{Type.t() => Type.t()}} | :error
  defp merge(map, [key, value | rest]),
    do: merge(Map.put(map, key, value), rest)

  defp merge(map, []), do: {:ok, map}

  defp merge(_map, [_arg]), do: :error

  @spec make_list([Type.t()]) :: Type.mal_list()
  def make_list(values), do: {:list, values, nil}

  @spec make_vector([Type.t()]) :: Type.vector()
  def make_vector(values), do: {:vector, values, nil}

  @spec make_map(%{Type.t() => Type.t()}) :: Type.mal_map()
  def make_map(pairs), do: {:map, pairs, nil}
end
