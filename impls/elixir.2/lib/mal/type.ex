defmodule Mal.Type do
  alias Mal.Env
  alias Mal.Type.Function

  @type t() ::
          integer()
          | String.t()
          | boolean()
          | nil
          | mal_keyword()
          | symbol()
          | mal_list()
          | vector()
          | mal_map()
          | Function.t()
          | mal_atom()
          | ([t()] -> t())

  @type mal_keyword() :: atom()
  @type symbol() :: {:symbol, binary()}
  @type mal_list() :: {:list, [t()], t()}
  @type vector() :: {:vector, [t()], t()}
  @type mal_map() :: {:map, %{t() => t()}, t()}
  @type builtin() :: ([t()], Env.t() -> {t(), Env.t()})
  @type mal_atom() :: {:atom, Env.Instance.id(), Env.Instance.atom_id()}
end
