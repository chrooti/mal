defmodule Mal do
  use Application

  def start(_type, _args) do
    if not IEx.started?() do
      start_repl()
    end

    {:ok, self()}
  end

  def start_repl() do
    step =
      System.fetch_env!("STEP")
      |> String.split("_")
      |> Enum.map_join(&String.capitalize/1)

    module_name = Module.safe_concat([Mal, step])
    module_name.start()
  end
end
