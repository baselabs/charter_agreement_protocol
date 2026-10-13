defmodule CharterAgreementProtocol.CryptoTrace do
  @moduledoc false

  def count(function, operation), do: count(:crypto, function, 5, operation)

  def count(module, function, arity, operation) do
    tracer = spawn_link(fn -> collect([]) end)
    :erlang.trace_pattern({module, function, arity}, true, [:local])
    :erlang.trace(self(), true, [:call, {:tracer, tracer}])

    try do
      result = operation.()
      reference = :erlang.trace_delivered(self())

      receive do
        {:trace_delivered, _process, ^reference} -> :ok
      end

      send(tracer, {:calls, self()})

      receive do
        {:calls, calls} -> {result, calls}
      end
    after
      :erlang.trace(self(), false, [:call])
      :erlang.trace_pattern({module, function, arity}, false, [:local])
      Process.exit(tracer, :normal)
    end
  end

  defp collect(calls) do
    receive do
      {:trace, _process, :call, {_module, _function, args}} -> collect([args | calls])
      {:calls, caller} -> send(caller, {:calls, Enum.reverse(calls)})
    end
  end
end
