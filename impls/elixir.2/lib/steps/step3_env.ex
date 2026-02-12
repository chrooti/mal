defmodule Mal.Step3Env do
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

    rep(env)
  end

  @spec rep(Env.t()) :: nil
  def rep(env) do
    case IO.gets("user> ") do
      :eof ->
        nil

      {:error, reason} ->
        raise reason

      input ->
        {ast, env} =
          input
          |> binary_part(0, byte_size(input) - 1)
          |> read()
          |> eval(env)

        ast
        |> print()
        |> IO.puts()

        rep(env)
    end
  rescue
    e in ParseError ->
      IO.puts("** ParseError: #{e.message}")
      rep(env)

    EmptyStatementError ->
      rep(env)

    e in EvalError ->
      IO.puts("** EvalError: #{e.message}")
      rep(env)

    e ->
      Exception.format(:error, e, __STACKTRACE__)
      |> IO.puts()

      rep(env)
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
