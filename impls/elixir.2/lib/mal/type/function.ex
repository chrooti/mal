defmodule Mal.Type.Function do
  alias Mal.Env
  alias Mal.Type

  defstruct [:body, :argnames, :env_id, :builtin, :meta, is_macro: false]

  @type t() :: %__MODULE__{
          body: Type.t() | nil,
          argnames: [Type.symbol()] | nil,
          env_id: Env.Instance.id() | nil,
          builtin: Type.builtin(),
          meta: Type.t(),
          is_macro: boolean()
        }
end
