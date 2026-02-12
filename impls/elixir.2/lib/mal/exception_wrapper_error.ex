defmodule Mal.ExceptionWrapperError do
  alias Mal.Env
  alias Mal.Printer
  alias Mal.Type

  defexception [:value, :env]

  @type t() :: %__MODULE__{
          value: Type.t(),
          env: Env.t()
        }

  def message(e), do: Printer.pr_str(e.value, e.env)
end
