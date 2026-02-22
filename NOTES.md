# Architectural Decisions and Trade-offs

## 1. Job Queuing (Oban)

### Queue-per-type vs. Single Queue Trade-offs

* **Single Queue:** A sudden influx of 50,000 slow, low-priority tasks can occupy all worker processes, starving critical tasks of resources.
* **Queue-per-priority:** Dedicated queues per priority level (e.g., critical, high, normal, low) guarantee reserved worker capacity for important jobs even during heavy low-priority load.
* **Queue-per-type:** Useful when job categories have drastically different resource profiles (e.g., imports are DB I/O heavy, reports are CPU intensive).

**Decision:** Queue-per-priority best satisfies strict execution order guarantees and predictable resource allocation.

Queue concurrency limits were configured assuming slightly higher frequency of low-priority jobs:
critical: 15
high: 15
normal: 15
low: 20

---

### Pruning Strategy

At 10,000 tasks per minute, approximately **14.4 million rows** are inserted into the `oban_jobs` table daily.

Without aggressive pruning:

* Postgres indexes will bloat.
* Sequential scans become increasingly expensive.
* Overall database performance will degrade significantly.

Since the `tasks` table serves as the permanent business record, Oban jobs should remain short-lived operational metadata.

**Decision:**

* `max_age`: 60 seconds.
* pruning `limit`: 10,000 jobs.

Additionally, a unique constraint on `task_id` was considered to prevent concurrent enqueueing of identical tasks.

---

## 2. Attempt Tracking

### `task_attempts` Table vs. Oban Telemetry Metrics

At a load of 10,000 tasks per minute, a dedicated `task_attempts` table would grow aggressively:

* ≈14.4 million rows/day baseline.
* With ~20% designed failures triggering retries, expected growth exceeds **18 million rows/day**.

This introduces multiple problems:

* **DB Query Latency:** Even indexed queries incur increasing disk I/O and CPU overhead as datasets grow.
* **Storage Growth:** Rapid table and index expansion increases maintenance costs.

Instead, a push-based in-memory aggregation model was chosen.

* **Telemetry + GenServer + ETS:**
  * A GenServer subscribes to `[:oban, :job, :*]` telemetry spans.
  * Calculations occur at event time rather than query time.
  * ETS provides fast shared-memory reads.

Advantages:

* **Speed:** Memory updates occur in microseconds versus millisecond-scale DB access.
* **Scalability:** The summary endpoint performs O(1) ETS reads, keeping response time constant regardless of dataset size.

---

### Individual Attempt Tracking

#### Current Implementation

Individual attempts are partially reflected via the `updated_at` timestamp on the Task record.

A GenServer:

* Initializes state from the database during startup.
* Subscribes to Oban telemetry spans.
* Updates state on every job lifecycle event.

Storage is handled via ETS with: read_concurrency: true


This provides:

* O(1) concurrent reads.
* Serialized updates through a single process, preventing race conditions.

---

### Planned Improvements

* Periodic DB state reconciliation (e.g., every 30 minutes) for cache invalidation.
* Measuring execution duration using `:timer.tc` and storing queue-type averages inside the cache manager.
* Using an embedded JSONB array on the `tasks` table to store attempt metadata:

  * timestamp
  * error message
  * execution duration

Localizing attempt history inside the task record avoids expensive joins during `GET /api/tasks/:id`.

---

## 3. Database

### Indexing for 10k/min Load

* **Partial Indexing:** Index on `status` and `inserted_at`, filtered only for `queued` and `processing`.

This keeps the index small and performant as millions of completed records accumulate.

* **Composite Index:** `(priority, inserted_at DESC)`.

This satisfies API sorting requirements directly at the storage layer.

---

### Concurrency & Integrity

`Repo.update_all` with a status guard ensures only one worker transitions a task into `processing`.

This prevents race conditions under high throughput.

---

### Planned Improvement

If strong task interdependencies appear:

* Introduce Ecto locks during execution.
* Combine locking with Oban rescheduling.
* Apply exponential backoff when long DB locks occur.

---

## 4. Supervision Tree & Fault Tolerance

* **Crash Recovery:** If `SummaryCache` crashes, it is restarted by `TaskPipeline.Supervisor`.

During initialization:

* A cold-boot database query recalculates status counts.

This ensures eventual cache consistency after failures.

---

### In-flight Tasks

Because Oban persists jobs in Postgres:

* Tasks running during system-wide crashes remain stored safely.
* Jobs retry automatically according to Oban configuration once nodes recover.

---

### Future Architectural Changes

To further isolate failures:

* Move `SummaryCache` and other custom logic into a dedicated Sub-Supervisor.

This prevents business logic crashes from affecting core infrastructure.

---

## 5. Testing

Testing coverage includes:

* API endpoints.
* Controllers.
* Contexts.
* Changesets.
* Oban job logic.

`ExCoveralls` was added for measurable coverage tracking: `mix coveralls.html`

Additionally, Oban Web was introduced for validating the end-to-end task lifecycle.

---

## 6. Time Management & Trade-offs (Hours vs. a Week)

### What Was Built Today

* Transactionally safe task pipeline using `Ecto.Multi` and Oban.
* High-performance telemetry-driven metrics using ETS.
* Production-ready schema with partial and composite indexing.

---

### What I Would Build Given a Full Week

* **Advanced Pagination:** Keyset (cursor-based) pagination for `GET /api/tasks` to avoid OFFSET degradation with millions of rows.
* **Observability:** OpenTelemetry distributed tracing with Prometheus/Grafana dashboards monitoring queue lag and worker utilization.
* **Rate Limiting:** Plug-based API rate limiter to prevent ingestion spikes overwhelming the database.
* **Dynamic Retries:** Exponential retry backoff depending on task type or priority.
* **DB Locks with Intelligent Rescheduling:** Explicit locking for interdependent jobs with exponential retry rescheduling (e.g., 2s → 4s → 8s).
