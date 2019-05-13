defmodule Crawly.RequestsStorage do
  @moduledoc """
  URLS Storage, a module responsible for storing urls for crawling
  """

  @doc """
  Storing URL

  ## Examples

      iex> Crawly.URLStorage.store_url
      :ok

  """

  require Logger

  use GenServer

  defstruct workers: %{}, pid_spiders: %{}

  alias Crawly.RequestsStorage

  def store(spider_name, requests) when is_list(requests) do
    GenServer.call(__MODULE__, {:store, {spider_name, requests}})
  end

  def store(spider_name, request) do
    store(spider_name, [request])
  end

  def pop(spider_name) do
    GenServer.call(__MODULE__, {:pop, spider_name})
  end

  def stats(spider_name) do
    GenServer.call(__MODULE__, {:stats, spider_name})
  end

  def start_worker(spider_name) do
    GenServer.call(__MODULE__, {:start_worker, spider_name})
  end

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    {:ok, %RequestsStorage{}}
  end

  def handle_call({:store, {spider_name, requests}}, _from, state) do
    %{workers: workers} = state

    msg =
      case Map.get(workers, spider_name) do
        nil ->
          {:error, :storage_worker_not_running}

        pid ->
          Crawly.RequestsStorage.Worker.store(pid, requests)
      end

    {:reply, msg, state}
  end

  def handle_call({:pop, spider_name}, _from, state = %{workers: workers}) do
    resp =
      case Map.get(workers, spider_name) do
        nil ->
          {:error, :no_worker_registered}

        pid ->
          Crawly.RequestsStorage.Worker.pop(pid)
      end

    {:reply, resp, state}
  end

  def handle_call({:stats, spider_name}, _from, state) do
    msg =
      case Map.get(state.workers, spider_name) do
        nil ->
          {:error, :storage_worker_not_running}

        pid ->
          Crawly.RequestsStorage.Worker.stats(pid)
      end

    {:reply, msg, state}
  end

  def handle_call({:start_worker, spider_name}, _from, state) do
    {msg, new_state} =
      case Map.get(state.workers, spider_name) do
        nil ->
          {:ok, pid} =
            DynamicSupervisor.start_child(
              Crawly.RequestsStorage.WorkersSup,
              {Crawly.RequestsStorage.Worker, spider_name}
            )

          Process.monitor(pid)

          new_workers = Map.put(state.workers, spider_name, pid)
          new_spider_pids = Map.put(state.pid_spiders, pid, spider_name)

          new_state = %{
            state
            | workers: new_workers,
              pid_spiders: new_spider_pids
          }

          {{:ok, pid}, new_state}

        _ ->
          {{:error, :already_started}, state.workers}
      end

    {:reply, msg, new_state}
  end

  # Clean up worker
  def handle_info({:DOWN, _ref, :process, pid, _}, state) do
    spider_name = Map.get(state.pid_spiders, pid)
    new_pid_spiders = Map.delete(state.pid_spiders, pid)
    new_workers = Map.delete(state.workers, spider_name)
    new_state =  %{state | workers: new_workers, pid_spiders: new_pid_spiders}

    {:noreply, new_state}
  end
end