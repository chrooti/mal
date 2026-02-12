defmodule Mal.Step4IfFnDo do
  alias Mal.Core
  alias Mal.EmptyStatementError
  alias Mal.Env
  alias Mal.EvalError
  alias Mal.ParseError
  alias Mal.Printer
  alias Mal.Reader
  alias Mal.Type
  alias Mal.Type.Function

  @spec start() :: nil
  def start() do
    env =
      Enum.reduce(Core.ns(), Env.new(), fn {key, value}, env ->
        Env.set(env, key, value)
      end)

    {_, env} = rep("(def! not (fn* (a) (if a false true)))", env)

    loop(env)
  end

  @spec loop(Env.t()) :: nil
  defp loop(env) do
    case IO.gets("user> ") do
      :eof ->
        nil

      {:error, reason} ->
        raise reason

      input ->
        {str, env} =
          input
          |> binary_part(0, byte_size(input) - 1)
          |> rep(env)

        IO.puts(str)

        loop(env)
    end
  rescue
    e in ParseError ->
      IO.puts("** ParseError: #{e.message}")
      loop(env)

    EmptyStatementError ->
      loop(env)

    e in EvalError ->
      IO.puts("** EvalError: #{e.message}")
      loop(env)

    e ->
      Exception.format(:error, e, __STACKTRACE__)
      |> IO.puts()

      loop(env)
  end

  @spec rep(String.t(), Env.t()) :: {String.t(), Env.t()}
  defp rep(input, env) do
    {ast, env} =
      input
      |> read()
      |> eval(env)

    {print(ast), env}
  end

  @spec read(String.t()) :: Type.t()
  defp read(input) do
    Reader.read_str(input)
  end

  @spec eval(Type.t(), Env.t()) :: {Type.t(), Env.t()}
  defp eval(ast, env) do
    case Env.get(env, "DEBUG-EVAL") do
      :error ->
        nil

      {:ok, value} when value in [nil, false] ->
        nil

      _ ->
        IO.puts("EVAL: " <> Printer.pr_str(ast))
    end

    case ast do
      {:symbol, symbol} ->
        {Env.get!(env, symbol), env}

      {:list, values = [_ | _], _meta} ->
        eval_list(values, env)

      {:vector, values, _meta} ->
        {values, env} =
          Enum.reduce(values, {[], env}, fn value, {values, env} ->
            {result, env} = eval(value, env)
            {[result | values], env}
          end)

        {values |> Enum.reverse() |> Core.make_vector(), env}

      {:map, pairs, _meta} ->
        {pairs, env} =
          Enum.reduce(pairs, {%{}, env}, fn {key, value}, {pairs, env} ->
            {result, env} = eval(value, env)
            {Map.put(pairs, key, result), env}
          end)

        {Core.make_map(pairs), env}

      ast ->
        {ast, env}
    end
  end

  @spec eval_list(nonempty_list(Type.t()), Env.t()) :: {Type.t(), Env.t()}
  defp eval_list([{:symbol, "def!"} | rest], env) do
    [{:symbol, key}, value] = rest

    {value, env} = eval(value, env)
    {value, Env.set(env, key, value)}
  end

  defp eval_list([{:symbol, "let*"} | rest], env) do
    [bindings, exprs] = rest

    inner_env =
      env
      |> Env.new_instance(env.curr_instance_id)
      |> parse_let_bindings(unwrap_seq(bindings))

    {result, inner_env} = eval(exprs, inner_env)
    {result, %{inner_env | curr_instance_id: env.curr_instance_id}}
  end

  defp eval_list([{:symbol, "do"} | rest], env) do
    Enum.reduce(rest, {nil, env}, fn ast, {_result, env} -> eval(ast, env) end)
  end

  defp eval_list([{:symbol, "if"} | rest], env) do
    [condition, if_true | rest] = rest

    {result, env} = eval(condition, env)

    if result in [nil, false] do
      case rest do
        [if_false] -> eval(if_false, env)
        [] -> {nil, env}
      end
    else
      eval(if_true, env)
    end
  end

  defp eval_list([{:symbol, "fn*"} | rest], env) do
    [argnames, body] = rest

    func = fn args, call_env ->
      inner_env =
        Env.new_instance(call_env, env.curr_instance_id, unwrap_seq(argnames), args)

      {result, inner_env} = eval(body, inner_env)

      {result, %{inner_env | curr_instance_id: call_env.curr_instance_id}}
    end

    {%Function{builtin: func}, env}
  end

  defp eval_list(values, env) do
    {values, env} =
      Enum.reduce(values, {[], env}, fn value, {values, env} ->
        {value, env} = eval(value, env)
        {[value | values], env}
      end)

    [func | args] = Enum.reverse(values)

    case func do
      %Function{} ->
        func.builtin.(args, env)

      _ ->
        raise EvalError,
          message: "Expected function, got " <> Printer.pr_str(func, env)
    end
  end

  @spec unwrap_seq(Type.mal_list() | Type.vector()) :: [Type.t()]
  defp unwrap_seq({type, values, _meta}) when type in [:list, :vector], do: values

  @spec parse_let_bindings(Env.t(), [Type.t()]) :: Env.t()
  defp parse_let_bindings(env, []), do: env

  defp parse_let_bindings(env, [{:symbol, key}, value | rest]) do
    {value, new_env} = eval(value, env)

    %{new_env | curr_instance_id: env.curr_instance_id}
    |> Env.set(key, value)
    |> parse_let_bindings(rest)
  end

  @spec print(Type.t()) :: String.t()
  defp print(ast) do
    Printer.pr_str(ast)
  end
end
