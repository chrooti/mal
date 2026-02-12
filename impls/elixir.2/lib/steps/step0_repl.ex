defmodule Mal.Step0Repl do
  @spec start() :: nil
  def start, do: rep()

  @spec rep() :: nil
  def rep do
    case IO.gets("user> ") do
      :eof ->
        nil

      {:error, reason} ->
        raise reason

      data ->
        data
        |> binary_part(0, byte_size(data) - 1)
        |> read()
        |> eval()
        |> print()
        |> IO.puts()

        rep()
    end
  end

  @spec read(String.t()) :: String.t()
  defp read(data) do
    data
  end

  @spec eval(String.t()) :: String.t()
  defp eval(data) do
    data
  end

  @spec print(String.t()) :: String.t()
  defp print(data) do
    data
  end
end
