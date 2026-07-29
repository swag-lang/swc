# Time and concurrency

[[Core.Time.Duration]] represents an interval expressed in seconds.
[[Core.Time.TimeSpan]] provides calendar-style components, while
[[Core.Time.DateTime]] represents a date and time. Use
[[Core.Time.Stopwatch]] for elapsed-time measurement and
[[Core.Time.FrameTiming]] for frame loops.

Concurrency is split into three layers:

| Need | API |
|---|---|
| A managed worker pool and parallel loops | [[Core.Jobs]] |
| A dedicated operating-system thread | [[Core.Threading.Thread]] |
| Mutual exclusion, events, and read/write locking | [[Core.Sync]] |
| Lock-free counters and values | [[Core.Atomic]] |

Prefer jobs for independent CPU work. Use a dedicated thread for a long-lived
blocking activity or a subsystem that requires thread affinity. Keep critical
sections small and never retain a pointer into a container while another thread
may resize that container.

Time values have different clocks and purposes. Wall-clock dates can change when
the system clock is adjusted; elapsed-time measurements should use the monotonic
timer exposed by the timing APIs.
