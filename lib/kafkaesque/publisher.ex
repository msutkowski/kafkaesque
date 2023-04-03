defmodule Kafkaesque.Publisher do
  @moduledoc """
  Stage that publishes messages in Kafka

  Takes 3 options:
  - `:producer_pid`: pid of the stage that will produce the messages.
  - `:client`: the client module that will be used to publish the messages.
  Defaults to `Kafkaesque.Clients.BrodClient`.
  - `:client_opts`: A list of options to be passed to the client on startup.
  Defaults to `[]`. The default client requires options, so this can be
  considered required for most use-cases.
  """

  use GenStage

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl GenStage
  def init(opts) do
    client_mod = Keyword.get(opts, :client, Kafkaesque.Clients.BrodClient)
    client_opts = Keyword.get(opts, :client_opts, [])
    producer_pid = Keyword.fetch!(opts, :producer_pid)
    min_demand = Keyword.get(opts, :publisher_min_demand, 190)
    max_demand = Keyword.get(opts, :publisher_max_demand, 200)

    {:ok, client} = client_mod.start_link(client_opts)

    {
      :producer_consumer,
      %{client_mod: client_mod, client: client, demand: 0},
      [subscribe_to: [{producer_pid, min_demand: min_demand, max_demand: max_demand}]]
    }
  end

  @impl GenStage
  def handle_events(messages, _from, state) do
    case state.client_mod.publish(state.client, messages) do
      {:ok, %{success: success, error: error}} ->
        events = [
          {:success_batch, Enum.map(success, & &1.id)},
          {:failure_batch, Enum.map(error, & &1.id)}
        ]

        {:noreply, events, state}

      _error ->
        {:noreply, [], state}
    end
  end
end
