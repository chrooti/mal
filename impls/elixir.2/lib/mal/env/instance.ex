defmodule Mal.Env.Instance do
  alias Mal.Core
  alias Mal.EvalError
  alias Mal.Type

  defstruct data: %{}, atoms: %{}, outer: nil

  @type t() :: %__MODULE__{
          data: %{String.t() => Type.t()},
          atoms: %{atom_id() => Type.t()},
          outer: id() | nil
        }

  @type id() :: integer()
  @type atom_id() :: integer()

  @spec new(id() | nil, [Type.t()], [Type.t()]) :: t()
  def new(outer, binds, exprs) do
    parse_args(%__MODULE__{outer: outer}, {binds, exprs}, binds, exprs)
  end

  @spec parse_args(t(), {[Type.t()], [Type.t()]}, [Type.t()], [Type.t()]) :: t()
  defp parse_args(instance, _original_args, [{:symbol, "&"} | binds], exprs) do
    case binds do
      [{:symbol, bind}] ->
        set(instance, bind, Core.make_list(exprs))

      _ ->
        raise EvalError, message: "& must be follwed by a single symbol"
    end
  end

  defp parse_args(instance, original_args, [{:symbol, bind} | binds], [expr | exprs]) do
    instance
    |> set(bind, expr)
    |> parse_args(original_args, binds, exprs)
  end

  defp parse_args(instance, _original_args, [], []), do: instance

  defp parse_args(instance, {binds, exprs}, _binds, _exprs) do
    binds_str = Core.prn(binds, ", ", instance.outer)
    exprs_str = Core.prn(exprs, ", ", instance.outer)
    raise EvalError, message: "Mismatched args: expected #{binds_str} but got #{exprs_str}"
  end

  @spec set(t(), String.t(), Type.t()) :: t()
  def set(instance, symbol, value),
    do: %{instance | data: Map.put(instance.data, symbol, value)}

  @spec set_atom(t(), atom_id(), Type.t()) :: t()
  def set_atom(instance, atom_id, value),
    do: %{instance | atoms: Map.put(instance.atoms, atom_id, value)}
end
