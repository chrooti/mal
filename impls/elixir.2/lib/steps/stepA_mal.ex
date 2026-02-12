defmodule Mal.StepaMal do
  alias Mal.Core
  alias Mal.EmptyStatementError
  alias Mal.Env
  alias Mal.EvalError
  alias Mal.Type.Function
  alias Mal.ParseError
  alias Mal.Printer
  alias Mal.Reader
  alias Mal.ExceptionWrapperError
  alias Mal.Type

  @spec start() :: nil
  def start() do
    env =
      Enum.reduce(Core.ns(), Env.new(), fn {key, value}, env ->
        Env.set(env, key, value)
      end)

    eval_builtin = fn [ast], call_env ->
      eval(ast, %{call_env | curr_instance_id: env.curr_instance_id})
    end

    env =
      env
      |> Env.set("eval", %Function{builtin: eval_builtin})
      |> Env.set("*host-language*", "elixir")

    {_, env} = rep("(def! not (fn* (a) (if a false true)))", env)

    {_, env} =
      rep(
        "(def! load-file (fn* (f) (eval (read-string (str \"(do \" (slurp f) \"\nnil)\")))))",
        env
      )

    {_, env} =
      rep(
        "(defmacro! cond (fn* (& xs) (if (> (count xs) 0) (list 'if (first xs) (if (> (count xs) 1) (nth xs 1) (throw \"odd number of forms to cond\")) (cons 'cond (rest (rest xs)))))))",
        env
      )

    case System.argv() do
      [filename | args] ->
        _ = rep("(load-file \"#{filename}\")", Env.set(env, "*ARGV*", Core.make_list(args)))
        nil

      [] ->
        {_, env} = rep("(println (str \"Mal [\" *host-language* \"]\"))", env)

        env
        |> Env.set("*ARGV*", Core.make_list([]))
        |> loop()
    end
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

    e in ExceptionWrapperError ->
      IO.puts("** Uncaught exception: #{Exception.message(e)}")
      loop(env)

    e ->
      Exception.format(:error, e, __STACKTRACE__)
      |> IO.puts()

      loop(env)
  end

  @spec rep(String.t(), Env.t()) :: {String.t(), Env.t()}
  defp rep(input, env) do
    {ast, new_env} =
      input
      |> read()
      |> eval(env)

    {print(ast, new_env), %{new_env | curr_instance_id: env.curr_instance_id}}
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
            {result, new_env} = eval(value, env)
            {[result | values], %{new_env | curr_instance_id: env.curr_instance_id}}
          end)

        {values |> Enum.reverse() |> Core.make_vector(), env}

      {:map, pairs, _meta} ->
        {pairs, env} =
          Enum.reduce(pairs, {%{}, env}, fn {key, value}, {pairs, env} ->
            {result, new_env} = eval(value, env)
            {Map.put(pairs, key, result), %{new_env | curr_instance_id: env.curr_instance_id}}
          end)

        {Core.make_map(pairs), env}

      ast ->
        {ast, env}
    end
  end

  @spec eval_list(nonempty_list(Type.t()), Env.t()) :: {Type.t(), Env.t()}
  defp eval_list([{:symbol, "def!"} | rest], env) do
    [{:symbol, key}, value] = rest

    curr_instance_id = env.curr_instance_id
    {value, env} = eval(value, env)
    {value, Env.set(%{env | curr_instance_id: curr_instance_id}, key, value)}
  end

  defp eval_list([{:symbol, "let*"} | rest], env) do
    [bindings, exprs] = rest

    inner_env =
      env
      |> Env.new_instance(env.curr_instance_id)
      |> parse_let_bindings(unwrap_seq(bindings))

    eval(exprs, inner_env)
  end

  defp eval_list([{:symbol, "do"} | rest], env) do
    eval_do(rest, env)
  end

  defp eval_list([{:symbol, "if"} | rest], env) do
    [condition, if_true | rest] = rest

    {result, new_env} = eval(condition, env)
    env = %{new_env | curr_instance_id: env.curr_instance_id}

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

    func = %Function{
      body: body,
      argnames: argnames,
      env_id: env.curr_instance_id,
      builtin: fn args, call_env ->
        call(call_env, env.curr_instance_id, argnames, args, body)
      end
    }

    {func, env}
  end

  defp eval_list([{:symbol, "quote"} | rest], env) do
    [arg] = rest
    {arg, env}
  end

  defp eval_list([{:symbol, "quasiquote"} | rest], env) do
    [arg] = rest
    eval(Core.quasiquote(arg), env)
  end

  defp eval_list([{:symbol, "defmacro!"} | rest], env) do
    [{:symbol, key}, value] = rest

    curr_instance_id = env.curr_instance_id
    {%Function{} = value, env} = eval(value, env)
    value = %{value | is_macro: true}

    {value, Env.set(%{env | curr_instance_id: curr_instance_id}, key, value)}
  end

  defp eval_list([{:symbol, "try*"} | rest], env) do
    case rest do
      [try_expr] ->
        eval(try_expr, env)

      [try_expr, {:list, [{:symbol, "catch*"}, {:symbol, exc_var}, catch_expr], nil}] ->
        try do
          eval(try_expr, env)
        rescue
          e in [ParseError, EmptyStatementError, EvalError] ->
            eval_catch(exc_var, Exception.message(e), catch_expr, env)

          e in ExceptionWrapperError ->
            eval_catch(exc_var, e.value, catch_expr, env)
        end

      _ ->
        raise EvalError, message: "malformed try expression"
    end
  end

  defp eval_list([func | args], env) do
    {func, new_env} = eval(func, env)
    env = %{new_env | curr_instance_id: env.curr_instance_id}

    case func do
      %Function{is_macro: true} ->
        {result, new_env} = call(env, func.env_id, func.argnames, args, func.body)
        eval(result, %{new_env | curr_instance_id: env.curr_instance_id})

      %Function{body: nil} ->
        {args, env} = eval_call_args(args, env)
        func.builtin.(args, env)

      %Function{} ->
        {args, env} = eval_call_args(args, env)
        call(env, func.env_id, func.argnames, args, func.body)

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

  @spec eval_do([Type.t()], Env.t()) :: {Type.t(), Env.t()}
  defp eval_do([], env), do: {nil, env}

  defp eval_do([ast], env), do: eval(ast, env)

  defp eval_do([ast | rest], env) do
    {_result, new_env} = eval(ast, env)
    eval_do(rest, %{new_env | curr_instance_id: env.curr_instance_id})
  end

  @spec call(
          env :: Env.t(),
          outer_env_id :: Env.Instance.id(),
          argnames :: Type.t(),
          args :: [Type.t()],
          body :: Type.t()
        ) :: {Type.t(), Env.t()}
  defp call(env, outer_env_id, argnames, args, body) do
    inner_env = Env.new_instance(env, outer_env_id, unwrap_seq(argnames), args)

    eval(body, inner_env)
  end

  @spec eval_call_args([Type.t()], Env.t()) :: {[Type.t()], Env.t()}
  defp eval_call_args(args, env) do
    {args, env} =
      Enum.reduce(args, {[], env}, fn arg, {args, env} ->
        {arg, new_env} = eval(arg, env)
        {[arg | args], %{new_env | curr_instance_id: env.curr_instance_id}}
      end)

    {Enum.reverse(args), env}
  end

  @spec eval_catch(String.t(), Type.t(), Type.t(), Env.t()) :: {Type.t(), Env.t()}
  defp eval_catch(exc_var, value, catch_expr, env) do
    inner_env =
      env
      |> Env.new_instance(env.curr_instance_id)
      |> Env.set(exc_var, value)

    eval(catch_expr, inner_env)
  end

  @spec print(Type.t(), Env.t()) :: String.t()
  defp print(ast, env) do
    Printer.pr_str(ast, env)
  end
end
