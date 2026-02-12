defmodule Mal.Printer do
  alias Mal.EvalError
  alias Mal.Env
  alias Mal.Type.Function
  alias Mal.Type

  @spec pr_str(Type.t() | (... -> any()), Env.t() | nil, boolean()) :: String.t()
  def pr_str(ast, env \\ nil, print_readably \\ true)

  def pr_str({:list, list, _meta}, env, print_readably),
    do: pr_sequence(list, "(", ")", env, print_readably)

  def pr_str(integer, _env, _print_readably) when is_integer(integer),
    do: Integer.to_string(integer)

  def pr_str(string, _env, _print_readably = false) when is_binary(string), do: string

  def pr_str(string, _env, _print_readably = true) when is_binary(string),
    do: "\"" <> escape_string(string) <> "\""

  def pr_str(true, _env, _print_readably), do: "true"
  def pr_str(false, _env, _print_readably), do: "false"
  def pr_str(nil, _env, _print_readably), do: "nil"
  def pr_str(atom, _env, _print_readably) when is_atom(atom), do: ":" <> Atom.to_string(atom)
  def pr_str({:symbol, symbol}, _env, _print_readably), do: symbol

  def pr_str({:vector, vector, _meta}, env, print_readably),
    do: pr_sequence(vector, "[", "]", env, print_readably)

  def pr_str({:atom, instance_id, atom_id}, env = %{}, print_readably),
    do: "(atom " <> pr_str(Env.get_atom(env, instance_id, atom_id), env, print_readably) <> ")"

  def pr_str(%Function{}, _env, _print_readably), do: "#<function>"

  def pr_str(func, _env, _print_readably) when is_function(func), do: "#<function>"

  def pr_str({:map, map, _meta}, env, print_readably) do
    elements =
      Enum.map_join(map, " ", fn {key, value} ->
        pr_str(key, env, print_readably) <> " " <> pr_str(value, env, print_readably)
      end)

    "{#{elements}}"
  end

  def pr_str(arg, _env, _print_readably) do
    raise EvalError, message: "Value #{inspect(arg)} unhandled by pr_str"
  end

  @spec escape_string(String.t(), String.t()) :: String.t()
  def escape_string(string, escaped \\ "")

  def escape_string("", escaped), do: escaped

  def escape_string(<<?\n, rest::binary>>, escaped),
    do: escape_string(rest, <<escaped::binary, ?\\, ?n>>)

  def escape_string(<<?\\, rest::binary>>, escaped),
    do: escape_string(rest, <<escaped::binary, ?\\, ?\\>>)

  def escape_string(<<?\", rest::binary>>, escaped),
    do: escape_string(rest, <<escaped::binary, ?\\, ?\">>)

  def escape_string(<<char, rest::binary>>, escaped),
    do: escape_string(rest, <<escaped::binary, char>>)

  @spec pr_sequence(
          [Type.t()],
          String.t(),
          String.t(),
          Env.t(),
          print_readably :: boolean()
        ) :: String.t()
  defp pr_sequence(seq, opening, closing, env, print_readably) do
    elements = Enum.map_join(seq, " ", &pr_str(&1, env, print_readably))

    opening <> elements <> closing
  end
end
