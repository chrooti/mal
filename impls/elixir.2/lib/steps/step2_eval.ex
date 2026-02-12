defmodule Mal.Step2Eval do
  alias Mal.Core
  alias Mal.EmptyStatementError
  alias Mal.EvalError
  alias Mal.ParseError
  alias Mal.Printer
  alias Mal.Reader
  alias Mal.Type

  @type mal_type() :: Type.t() | (mal_type() -> mal_type())

  @spec start() :: nil
  def start do
    rep(%{
      "+" => fn [a, b] -> a + b end,
      "-" => fn [a, b] -> a - b end,
      "*" => fn [a, b] -> a * b end,
      "/" => fn [a, b] -> Integer.floor_div(a, b) end
    })
  end

  @spec rep(%{String.t() => mal_type()}) :: nil
  def rep(env) do
    case IO.gets("user> ") do
      :eof ->
        nil

      {:error, reason} ->
        raise reason

      input ->
        input
        |> binary_part(0, byte_size(input) - 1)
        |> read()
        |> eval(env)
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

  @spec eval(mal_type(), %{String.t() => mal_type()}) :: mal_type()
  defp eval(ast, env) do
    case Map.fetch(env, "DEBUG-EVAL") do
      :error ->
        nil

      {:ok, value} when value in [nil, false] ->
        nil

      _ ->
        IO.puts("EVAL: " <> Printer.pr_str(ast))
    end

    case ast do
      {:symbol, symbol} ->
        case Map.fetch(env, symbol) do
          {:ok, value} -> value
          :error -> raise EvalError, message: "#{symbol} not found in env!"
        end

      {:list, [name | rest], _meta} ->
        func = eval(name, env)
        args = Enum.map(rest, &eval(&1, env))

        case func do
          func when is_function(func) ->
            func.(args)

          _ ->
            raise EvalError, message: "Expected function"
        end

      {:vector, values, _meta} ->
        values
        |> Enum.map(&eval(&1, env))
        |> Core.make_vector()

      {:map, pairs, _meta} ->
        pairs
        |> Map.new(fn {key, value} -> {key, eval(value, env)} end)
        |> Core.make_map()

      ast ->
        ast
    end
  end

  @spec print(mal_type()) :: String.t()
  defp print(ast) do
    Printer.pr_str(ast)
  end
end
