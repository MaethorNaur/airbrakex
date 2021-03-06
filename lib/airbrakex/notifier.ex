defmodule Airbrakex.Notifier do
  @moduledoc false
  use HTTPoison.Base
  alias Airbrakex.Config

  @request_headers [{"Content-Type", "application/json"}]
  @default_endpoint "https://airbrake.io"
  @default_env Mix.env()

  @info %{
    name: "Airbrakex",
    version: Airbrakex.Mixfile.project()[:version],
    url: Airbrakex.Mixfile.project()[:package][:links][:github]
  }

  def notify(error, options \\ []) do
    payload =
      %{}
      |> add_notifier
      |> add_error(error)
      |> add_context(Keyword.get(options, :context))
      |> add(:session, Keyword.get(options, :session))
      |> add(:backtrace, Keyword.get(options, :backtrace))
      |> add_params(Keyword.get(options, :params, %{}))
      |> add(:environment, Keyword.get(options, :environment, %{}))
      |> Poison.encode!()

    post(url(), payload, @request_headers)
  end

  defp add_notifier(payload) do
    payload |> Map.put(:notifier, @info)
  end

  defp add_error(payload, nil), do: payload

  defp add_error(payload, error) do
    payload |> Map.put(:errors, [error])
  end

  defp add_params(payload, params) do
    params =
      params
      |> Map.put_new(:node_ip, node_ip())

    payload |> Map.put(:params, params)
  end

  defp add_context(payload, nil) do
    payload
    |> Map.put(:context, %{environment: environment(), remoteAddr: node_ip(), language: "Elixir"})
  end

  defp add_context(payload, context) do
    context =
      context
      |> Map.put_new(:environment, environment())
      |> Map.put_new(:remoteAddr, node_ip())
      |> Map.put_new(:language, "Elixir")

    payload |> Map.put(:context, context)
  end

  defp add(payload, _key, nil), do: payload
  defp add(payload, key, value), do: payload |> Map.put(key, value)

  defp url do
    project_id = Config.get(:airbrakex, :project_id)
    project_key = Config.get(:airbrakex, :project_key)
    endpoint = Config.get(:airbrakex, :endpoint, @default_endpoint)

    "#{endpoint}/api/v3/projects/#{project_id}/notices?key=#{project_key}"
  end

  defp environment do
    Config.get(:airbrakex, :environment, @default_env)
  end

  defp node_ip, do: Node.self() |> to_string |> String.split("@") |> Enum.at(1)
end
