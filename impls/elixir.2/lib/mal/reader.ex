defmodule Mal.Reader do
  alias Mal.EmptyStatementError
  alias Mal.ParseError
  alias Mal.Type

  defstruct tokens: []

  @type t() :: %__MODULE__{
          tokens: [String.t()]
        }

  @token_regex ~r/[\s,]*(~@|[\[\]{}()'`~^@]|"(?:\\.|[^\\"])*"?|;.*|[^\s\[\]{}('"`,;)]*)/

  @spec read_str(String.t()) :: Type.t()
  def read_str(str) do
    tokens = tokenize(str)

    if tokens == [] do
      raise %EmptyStatementError{}
    end

    reader = %__MODULE__{tokens: tokens}
    {%__MODULE__{tokens: []}, ast} = read_form(reader)
    ast
  end

  @spec tokenize(String.t()) :: [String.t()]
  defp tokenize(str) do
    str = String.trim(str)

    Regex.scan(@token_regex, str, capture: :all_but_first)
    |> Enum.map(fn [match] -> match end)
    # always matches an empty string as the last match
    |> List.delete_at(-1)
    # remove comments
    |> Enum.reject(fn
      # comments
      <<?\;, _::binary>> -> true
      # empty match
      "" -> true
      _ -> false
    end)
  end

  @spec read_form(t()) :: {t(), Type.t()}
  defp read_form(reader) do
    case peek(reader) do
      "(" -> read_list(next(reader))
      "[" -> read_vector(next(reader))
      "{" -> read_map(next(reader))
      "'" -> read_alias(next(reader), "quote")
      "`" -> read_alias(next(reader), "quasiquote")
      "~" -> read_alias(next(reader), "unquote")
      "~@" -> read_alias(next(reader), "splice-unquote")
      "@" -> read_alias(next(reader), "deref")
      "^" -> read_alias2(next(reader), "with-meta")
      token -> {next(reader), read_atom(token)}
    end
  end

  @spec read_list(t()) :: {t(), Type.t()}
  defp read_list(reader) do
    {reader, values} = read_sequence(reader, ")")
    {reader, {:list, values, nil}}
  end

  @spec read_vector(t()) :: {t(), Type.t()}
  defp read_vector(reader) do
    {reader, values} = read_sequence(reader, "]")
    {reader, {:vector, values, nil}}
  end

  @spec read_sequence(t(), binary(), [Type.t()]) :: {t(), [Type.t()]}
  defp read_sequence(reader, end_token, seq \\ []) do
    case peek(reader) do
      ^end_token ->
        {next(reader), Enum.reverse(seq)}

      _ ->
        {reader, ast} = read_form(reader)
        read_sequence(reader, end_token, [ast | seq])
    end
  end

  @spec read_map(t(), map()) :: {t(), Type.t()}
  defp read_map(reader, pairs \\ %{}) do
    case peek(reader) do
      "}" ->
        {next(reader), {:map, pairs, nil}}

      _ ->
        {reader, key} = read_form(reader)
        {reader, value} = read_form(reader)

        read_map(reader, Map.put(pairs, key, value))
    end
  end

  @spec read_alias(t(), String.t()) :: {t(), Type.t()}
  defp read_alias(reader, alias) do
    {reader, ast} = read_form(reader)

    {reader, {:list, [{:symbol, alias}, ast], nil}}
  end

  @spec read_alias2(t(), String.t()) :: {t(), Type.t()}
  defp read_alias2(reader, alias) do
    {reader, ast1} = read_form(reader)
    {reader, ast2} = read_form(reader)

    {reader, {:list, [{:symbol, alias}, ast2, ast1], nil}}
  end

  @spec read_atom(String.t()) :: Type.t()
  defp read_atom(token) do
    case token do
      "false" ->
        false

      "true" ->
        true

      "nil" ->
        nil

      ":" <> keyword ->
        String.to_atom(keyword)

      "\"" <> string ->
        if byte_size(string) == 0 or :binary.last(string) != ?\" do
          raise ParseError, message: "EOF: unterminated string"
        end

        string
        |> binary_part(0, byte_size(string) - 1)
        |> unescape_string()

      symbol_or_integer ->
        case Integer.parse(symbol_or_integer) do
          {integer, ""} -> integer
          :error -> {:symbol, symbol_or_integer}
        end
    end
  end

  @spec unescape_string(String.t(), String.t()) :: String.t()
  defp unescape_string(string, unescaped \\ "")

  defp unescape_string("", unescaped),
    do: unescaped

  defp unescape_string(<<?\\, rest::binary>>, unescaped) do
    case rest do
      <<char, rest::binary>> ->
        unescape_string(rest, <<unescaped::binary, unquote_char(char)>>)

      "" ->
        raise ParseError, message: "EOF: unterminated escape sequence"
    end
  end

  defp unescape_string(<<char, rest::binary>>, unescaped),
    do: unescape_string(rest, <<unescaped::binary, char>>)

  @spec unquote_char(?n) :: ?\n
  defp unquote_char(?n), do: ?\n

  @spec unquote_char(?\\) :: ?\\
  defp unquote_char(?\\), do: ?\\

  @spec unquote_char(?") :: ?"
  defp unquote_char(?"), do: ?"

  defp unquote_char(_char) do
    raise ParseError, message: "EOF: Unexpected escape sequence"
  end

  @spec next(t()) :: t()
  defp next(reader), do: %{reader | tokens: tl(reader.tokens)}

  @spec peek(t()) :: String.t()
  defp peek(%__MODULE__{tokens: [token | _]}), do: token

  defp peek(%__MODULE__{tokens: []}) do
    raise ParseError, message: "EOF: unterminated token string"
  end
end
