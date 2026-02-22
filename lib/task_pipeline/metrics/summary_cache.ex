defmodule TaskPipeline.Metrics.SummaryCache do
  use GenServer
  import Ecto.Query

  alias TaskPipeline.Repo

  @table :task_summary_metrics
  @cache_key :counts

  ## ---------- Public API ----------

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_counts do
    [{@cache_key, counts}] = :ets.lookup(@table, @cache_key)
    counts
  end

  def reset! do
    :ets.insert(@table, {@cache_key, empty_counts()})
  end

  ## ---------- GenServer ----------

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])

    attach_telemetry()

    send(self(), :refresh_from_db)

    {:ok, empty_counts()}
  end

  @impl true
  def handle_info(:refresh_from_db, _state) do
    counts =
      calculate_counts_from_db()
      |> Map.merge(empty_counts())

    :ets.insert(@table, {@cache_key, counts})
    {:noreply, counts}
  end

  ## ---------- Telemetry Handler ----------

  def handle_event([:oban, :job, :start], _measurements, _meta, _config) do
    shift_count(:queued, :processing)
  end

  def handle_event([:oban, :job, :stop], _m, meta, _c) do
    case meta.state do
      :success ->
        shift_count(:processing, :completed)

      :cancelled ->
        shift_count(:processing, :failed)

      :discarded ->
        shift_count(:processing, :failed)
    end
  end

  def handle_event([:oban, :job, :exception], _m, meta, _c) do
    if meta.attempt >= meta.max_attempts do
      shift_count(:processing, :failed)
    else
      shift_count(:processing, :queued)
    end
  end

  ## ---------- Internal Logic ----------

  defp attach_telemetry do
    :telemetry.attach_many(
      "oban-summary-cache",
      [
        [:oban, :job, :start],
        [:oban, :job, :stop],
        [:oban, :job, :exception]
      ],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  defp shift_count(old, new) do
    counts = get_counts()

    counts =
      counts
      |> decrement(old)
      |> increment(new)

    update_ets(counts)
  end

  defp update_ets(counts) do
    :ets.insert(@table, {@cache_key, counts})
  end

  ## ---------- Counting ----------

  defp calculate_counts_from_db do
    TaskPipeline.Tasks.Task
    |> group_by([t], t.status)
    |> select([t], {t.status, count(t.id)})
    |> Repo.all()
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.merge(empty_counts())
  end

  ## ---------- Counters ----------

  defp increment(counts, status) do
    key = to_string(status)
    Map.update(counts, key, 1, &(&1 + 1))
  end

  defp decrement(counts, status) do
    key = to_string(status)
    Map.update(counts, key, 0, &max(0, &1 - 1))
  end

  defp empty_counts do
    %{
      "queued" => 0,
      "processing" => 0,
      "completed" => 0,
      "failed" => 0
    }
  end
end
