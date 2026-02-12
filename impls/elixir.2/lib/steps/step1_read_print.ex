defmodule Mal.Step1ReadPrint do
  alias Mal.EmptyStatementError
  alias Mal.ParseError
  alias Mal.Printer
  alias Mal.Reader
  alias Mal.Type

  @spec start() :: nil
  def start, do: rep()

  @spec rep() :: nil
  def rep do
    case IO.gets("user> ") do
      :eof ->
        nil

      {:error, reason} ->
        raise reason

      input ->
        input
        |> binary_part(0, byte_size(input) - 1)
        |> read()
        |> eval()
        |> print()
        |> IO.puts()

        rep()
    end
  rescue
    e in ParseError ->
      IO.puts("** ParseError: #{e.message}")
      rep()

    EmptyStatementError ->
      rep()
  end

  @spec read(String.t()) :: Type.t()
  defp read(input) do
    Reader.read_str(input)
  end

  @spec eval(Type.t()) :: Type.t()
  defp eval(ast) do
    ast
  end

  @spec print(Type.t()) :: String.t()
  defp print(ast) do
    Printer.pr_str(ast)
  end
end
