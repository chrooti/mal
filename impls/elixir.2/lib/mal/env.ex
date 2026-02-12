defmodule Mal.Env do
  alias Mal.Env.Instance
  alias Mal.EvalError
  alias Mal.Type

  defstruct instances: %{},
            last_instance_id: 0,
            curr_instance_id: 0,
            last_atom_id: 0

  @type t() :: %__MODULE__{
          instances: %{Instance.id() => Instance.t()},
          last_instance_id: Instance.id(),
          curr_instance_id: Instance.id(),
          last_atom_id: Instance.atom_id()
        }

  @spec new() :: t()
  def new(), do: new_instance(%__MODULE__{})

  @spec new_instance(t(), Instance.id() | nil, [Type.t()], [Type.t()]) :: t()
  def new_instance(env, outer \\ nil, binds \\ [], exprs \\ []) do
    instance = Instance.new(outer, binds, exprs)

    instance_id = env.last_instance_id + 1

    %{
      env
      | instances: Map.put(env.instances, instance_id, instance),
        last_instance_id: instance_id,
        curr_instance_id: instance_id
    }
  end

  @spec get!(t(), String.t()) :: Type.t()
  def get!(env, symbol) do
    case get(env, symbol) do
      :error ->
        raise EvalError, message: "\'#{symbol}\' not found"

      {:ok, value} ->
        value
    end
  end

  @spec get(t(), String.t()) :: {:ok, Type.t()} | :error
  def get(env, symbol), do: do_get(env, env.curr_instance_id, symbol)

  @spec do_get(t(), Instance.id(), String.t()) :: {:ok, Type.t()} | :error
  defp do_get(env, id, symbol) do
    instance = Map.fetch!(env.instances, id)

    case instance do
      %{data: %{^symbol => value}} -> {:ok, value}
      %{outer: nil} -> :error
      %{outer: outer} -> do_get(env, outer, symbol)
    end
  end

  @spec set(t(), String.t(), Type.t()) :: t()
  def set(env, symbol, value),
    do: %{
      env
      | instances:
          Map.update!(env.instances, env.curr_instance_id, &Instance.set(&1, symbol, value))
    }

  @spec get_atom(t(), Instance.id(), Instance.atom_id()) :: Type.t()
  def get_atom(env, instance_id, atom_id) do
    %{^instance_id => %{atoms: %{^atom_id => value}}} = env.instances
    value
  end

  @spec set_atom(t(), Instance.id(), Instance.atom_id(), Type.t()) :: t()
  def set_atom(env, instance_id, atom_id, value),
    do: %{
      env
      | instances: Map.update!(env.instances, instance_id, &Instance.set_atom(&1, atom_id, value))
    }

  @spec make_atom(t(), Type.t()) :: {Instance.id(), Instance.atom_id(), t()}
  def make_atom(env, value) do
    instance_id = env.curr_instance_id
    atom_id = env.last_atom_id + 1

    {instance_id, atom_id, set_atom(%{env | last_atom_id: atom_id}, instance_id, atom_id, value)}
  end
end
