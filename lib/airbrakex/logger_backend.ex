defmodule Airbrakex.LoggerBackend do
  @moduledoc """
  A Logger backend to send exceptions from logs to the `airbrake`

  ## Usage

  ```elixir
  config :logger,
    backends: [Airbrakex.LoggerBackend]
  ```
  """

  @behaviour :gen_event

  alias Airbrakex.{ExceptionParser, LoggerParser, Notifier}

  def init(__MODULE__) do
    {:ok, configure([])}
  end

  def handle_call({:configure, opts}, _state) do
    {:ok, :ok, configure(opts)}
  end

  def handle_event({_level, gl, _event}, state) when node(gl) != node() do
    {:ok, state}
  end

  def handle_event({level, _gl, event}, %{metadata: keys} = state) do
    if proceed?(event) and meet_level?(level, state.level) do
      post_event(level, event, keys)
    end

    {:ok, state}
  end

  def handle_event(:flush, state) do
    {:ok, state}
  end

  def handle_info(_message, state) do
    {:ok, state}
  end

  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end

  defp proceed?({Logger, _msg, _ts, meta}) do
    Keyword.get(meta, :airbrakex, true)
  end

  defp meet_level?(lvl, min) do
    Logger.compare_levels(lvl, min) != :lt
  end

  defp post_event(level, {Logger, msg, _ts, meta}, keys) do
    msg = IO.chardata_to_string(msg)
    meta = take_into_map(meta, keys)

    args =
      msg
      |> LoggerParser.parse()
      |> merge_backtrace(level, meta)

    apply(Notifier, :notify, args)
  end

  defp merge_backtrace(error, level, meta) do
    backtrace = Map.get(meta, :backtrace)

    error =
      error
      |> Map.merge(
        if backtrace != nil,
          do: %{backtrace: backtrace |> ExceptionParser.stacktrace()},
          else: %{}
      )

    [
      error,
      [
        context: %{severity: level},
        params: meta |>
        Enum.filter(&(elem(&1, 0) != :backtrace))
        |> Enum.into(%{})
      ]
    ]
  end

  defp take_into_map(metadata, keys) do
    Enum.reduce(metadata, %{}, fn {key, val}, acc ->
      if key in keys, do: Map.put(acc, key, val), else: acc
    end)
  end

  defp configure(opts) do
    config =
      :logger
      |> Application.get_env(__MODULE__, [])
      |> Keyword.merge(opts)

    Application.put_env(:logger, __MODULE__, config)

    %{
      level: Application.get_env(:airbrakex, :logger_level, :error),
      metadata: Keyword.get(config, :metadata, [])
    }
  end
end
