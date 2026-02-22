# Architectural Decisions and Trade-offs

## 1. Job Queuing (Oban)

### Queue-per-type vs. Single Queue Trade-offs
* **Single Queue:** A sudden influx of 50,000 slow, low-priority tasks will occupy all worker processes, starving critical tasks of resources.
* **Queue-per-priority:** Dedicates specific queues to priorities (e.g., critical, high, default). This guarantees that critical tasks always have dedicated worker capacity, even if the system is flooded with low-priority jobs.
* **Queue-per-type:** Ideal if tasks have vastly different resource profiles (e.g., imports require heavy DB I/O, while reports require heavy CPU).

**Decision:** Queue-per-priority is the better design choice to satisfy strict execution order constraints. Queue concurrency limits were set predicting that low-priority jobs will occur slightly more often: `critical: 15`, `high: 15`, `normal: 15`, `low: 20`.

### Pruning Strategy
At 10,000 tasks/minute, we are inserting approximately 14.4 million rows into the `oban_jobs` table every day. If we do not prune aggressively, Postgres index sizes will bloat, sequential scans will become fatal, and performance will collapse. Since our `tasks` table acts as the permanent business record, Oban jobs should be pruned immediately or within a minute of completion.

**Decision:** Implemented a `max_age` of 60 seconds with a limit of 10,000 jobs. A unique constraint on `task_id` was also considered to prevent the exact same task from being enqueued concurrently.

---

## 2. Attempt Tracking

### `task_attempts` Table vs. Oban Metrics
At a scale of 10,000 tasks per minute, a dedicated `task_attempts` table will grow at an aggressive rate of 14.4+ million rows per day. Since 20% of tasks are designed to fail and trigger retries, the actual row count will likely exceed 18 million rows daily. 

* **DB Query Latency:** Querying a table with millions of rows involves disk I/O and CPU overhead that scales with the data size, even with indexing.
* **GenServer/ETS:** By using a GenServer that reacts to `[:oban, :job, :*]` telemetry spans, we shift the calculation cost to the exact moment the event happens (a "push" model).
* **Speed:** Updates to the GenServer state and ETS table happen in microseconds (memory access) rather than milliseconds (disk/DB access).
* **Scalability:** The summary endpoint performs an O(1) read from ETS, meaning the API response time remains constant regardless of whether the database contains 1,000 or 100,000,000 tasks.

### Individual Attempt Tracking
**Current Implementation:** Individual attempts are partially tracked via the `updated_at` timestamp on the Task record, which reflects the most recent state change. I implemented a GenServer subscribed to Oban telemetry spans. The GenServer initializes state from the database and updates state on every span update. Storage is handled via ETS with `read_concurrency: true`, providing O(1) reads while serializing state updates through a single process to avoid race conditions.

**Planned Improvement:**
* Periodic state overrides from the DB (e.g., every 30 minutes) for cache invalidation.
* Measuring job execution by wrapping the job in a `:timer.tc` function and storing the average time in the cache manager by queue type.
* Using an embedded JSONB array on the `tasks` table to store attempt metadata (timestamp, error message, and execution duration). Storing attempts directly on the task record keeps the data localized and avoids expensive joins during the `GET /api/tasks/:id` lookup.

---

## 3. Database

### Indexing for 10k/min Load
* **Partial Indexing:** Created an index on `status` and `inserted_at` filtered specifically for `queued` and `processing` states. This keeps the index footprint small and highly performant as the table accumulates millions of "completed" rows.
* **Composite Index:** Implemented a composite index on `(priority, inserted_at DESC)` to satisfy the required API sort order directly at the storage layer.

### Concurrency & Integrity
Used `Repo.update_all` with a status check to ensure only one worker can successfully transition a task to `processing`. This prevents race conditions at high throughput.

**Planned Improvement:** If tasks heavily depend on each other, I would consider Ecto locks when performing the job instead of a simple status check, combined with Oban rescheduling (using an exponential backoff strategy in the case of long DB locks).

---

## 4. Supervision Tree & Fault Tolerance

* **Crash Recovery:** If `SummaryCache` crashes, it is restarted by the `TaskPipeline.Supervisor`. Upon initialization, it executes a "cold boot" query against the database to recalculate the current status counts. This ensures the cache remains eventually consistent even after a process failure.
* **In-flight Tasks:** Because Oban is backed by Postgres, any in-flight tasks during a system-wide crash are preserved in the DB. They will be retried based on their specific Oban configuration once the node recovers.

**Future Architectural Changes:** To further improve fault tolerance, I would move the `SummaryCache` and other custom logic into a dedicated Sub-Supervisor. This isolates custom business logic failures from core infrastructure.

---

## 5. Testing Strategy
Besides covering the API, controllers, changesets, contexts, and Oban logic, the `ExCoveralls` tool was added to track test coverage effectively (`mix coveralls.html`).

---

## 6. Time Management & Trade-offs (Hours vs. a Week)

### What Was Built Today
* A hardened, transactionally safe task pipeline using `Ecto.Multi` and Oban.
* High-performance metrics tracking using Telemetry and ETS to bypass database bottlenecks.
* A production-ready database schema with partial and composite indexing.

### What I Would Build Given a Full Week
* **Advanced Pagination:** Implement keyset (cursor-based) pagination for the `GET /api/tasks` endpoint to handle millions of records without the performance degradation of `OFFSET`.
* **Observability:** Integrate OpenTelemetry for distributed tracing and Prometheus/Grafana dashboards to monitor queue lag and worker utilization.
* **Rate Limiting:** Add a plug-based rate limiter to the API to prevent ingestion spikes from overwhelming the database.
* **Dynamic Retries:** Implement a backoff strategy where retries are delayed exponentially based on the task type or priority.
* **DB Locks with Intelligent Rescheduling:** For inter-dependent jobs, implement explicit database locks to ensure retries are utilized effectively. If a job fails due to a lock, it would be rescheduled with exponential backoff (e.g., 2s, 4s, 8s).