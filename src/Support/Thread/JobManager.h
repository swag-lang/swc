#pragma once
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

class JobManager
{
public:
    JobManager()                             = default;
    JobManager(const JobManager&)            = delete;
    JobManager& operator=(const JobManager&) = delete;
    ~JobManager();

    void        setup(const CommandLine& cmdLine);
    JobClientId newClientId();

    void enqueue(Job& job, JobPriority priority, JobClientId client = 0);
    void waitingJobs(std::vector<Job*>& waiting, JobClientId client) const;

    // Dependency-driven wake: move every job parked on this exact dependency from
    // Waiting to Ready. Cheap no-op when nobody waits on it.
    void wake(const WaitKey& key);
    void refreshJitWait(const TaskContext* owner);

    bool wakeAll(JobClientId client);
    void waitAll();
    void waitAll(JobClientId client);

    // Runs `fn(workerCtx, index)` for index in [0, count). Each worker owns a
    // TaskContext copy and claims indices atomically. The caller must restrict shared
    // access to thread-safe services and write each result to its own indexed slot.
    template<typename T>
    void parallelForIndexed(TaskContext& ctx, uint32_t count, JobKind kind, JobClientId clientId, const T& fn, JobPriority priority = JobPriority::Normal)
    {
        if (count == 0)
            return;

        if (count == 1 || isSingleThreaded() || numWorkers() == 0)
        {
            for (uint32_t i = 0; i < count; ++i)
                fn(ctx, i);
            return;
        }

        class WorkerJob final : public Job
        {
        public:
            WorkerJob(const TaskContext& ctx, JobKind kind, std::atomic<uint32_t>& next, uint32_t count, const T& fn) :
                Job(ctx, kind),
                next_(&next),
                count_(count),
                fn_(&fn)
            {
            }

            JobResult exec() override
            {
                for (uint32_t i = next_->fetch_add(1, std::memory_order_relaxed); i < count_; i = next_->fetch_add(1, std::memory_order_relaxed))
                    (*fn_)(this->ctx(), i);
                return JobResult::Done;
            }

        private:
            std::atomic<uint32_t>* next_;
            uint32_t               count_;
            const T*               fn_;
        };

        const uint32_t        workerCount = std::min(count, numWorkers());
        std::atomic<uint32_t> nextIndex{0};

        std::vector<std::unique_ptr<WorkerJob>> jobs;
        jobs.reserve(workerCount);
        for (uint32_t i = 0; i < workerCount; ++i)
            jobs.push_back(std::make_unique<WorkerJob>(ctx, kind, nextIndex, count, fn));
        for (auto& job : jobs)
            enqueue(*job, priority, clientId);
        waitAll(clientId);
    }

#if SWC_DEV_MODE
    // The driver counts each semantic barrier round; the rest is counted under the scheduler lock.
    void noteBarrierRound();
    void printStats(const TaskContext& ctx) const;

    // Names what the driver is doing, so serial and starved worker time can be charged to it.
    // Phases nest; the innermost one owns the time. The name must outlive the report.
    class StatsPhase
    {
    public:
        StatsPhase(JobManager& manager, const char* name);
        ~StatsPhase();
        StatsPhase(const StatsPhase&)            = delete;
        StatsPhase& operator=(const StatsPhase&) = delete;

    private:
        JobManager* manager_  = nullptr;
        const char* previous_ = nullptr;
    };
#endif

    uint32_t      numWorkers() const noexcept { return configuredWorkerCount_; }
    uint32_t      randSeed() const noexcept { return randSeed_; }
    static size_t threadIndex() noexcept { return threadIndex_; }
    bool          isSingleThreaded() const noexcept { return singleThreaded_; }

    // A private storage slot for this pool's worker or setup thread. External
    // callers have no slot, even though the legacy TLS threadIndex defaults to zero.
    std::optional<size_t> currentThreadIndex() const noexcept;

private:
    struct ClientState
    {
        size_t     readyRunning = 0;
        JobRecord* waitingHead  = nullptr;
    };

    void       pushReady(JobRecord* rec, JobPriority priority);
    JobRecord* popReadyLocked();
    JobRecord* popReadyForClientLocked(JobClientId client);
    bool       isDrainedLocked() const;

    static JobResult              executeJob(Job& job);
    void                          handleJobResultLocked(JobRecord* rec, JobResult res);
    void                          workerLoop();
    static std::optional<WaitKey> computeWaitKey(const TaskState& state);
    void                          parkLocked(ClientState& client, JobRecord* rec, const TaskState& state);
    void                          unregisterWaiterLocked(ClientState& client, JobRecord* rec);
    void                          requeueWaitingLocked(ClientState& client, JobRecord* rec);
    void                          growWorkersForLoadLocked();

    void shutdown() noexcept;

    // Setup
    bool                                  singleThreaded_        = false;
    const CommandLine*                    cmdLine_               = nullptr;
    uint32_t                              randSeed_              = 0;
    uint32_t                              configuredWorkerCount_ = 0;
    static thread_local size_t            threadIndex_;
    static thread_local const JobManager* threadManager_;
    std::thread::id                       setupThreadId_;

    // Ready queues per priority (store Record* for direct access).
    std::deque<JobRecord*> readyQ_[3];

    // Queue and completion predicates share mtx_ with their condition-variable waits.
    // No worker polls these counters outside the scheduler lock.
    size_t readyCount_    = 0;
    size_t activeWorkers_ = 0;

    // Threading & sync
    std::vector<std::thread> workers_;
    mutable std::mutex       mtx_;
    std::condition_variable  cv_;     // work available / shutdown
    std::condition_variable  idleCv_; // becomes idle (global or per-client)

    // Lifecycle flags
    std::atomic<bool> accepting_{false};
    std::atomic<bool> joined_{false};

    // Client counters and sleeping lists share mtx_. Ready/running jobs need no
    // secondary live-record registry or per-job hash node.
    std::atomic<JobClientId>                     nextClientId_{1}; // start at 1, 0 reserved as "default client"
    std::unordered_map<JobClientId, ClientState> clients_;
    // Enqueue assigns every index while holding mtx_.
    uint32_t nextIndex_ = 0;

    // Sleeping jobs indexed by the exact dependency they wait on, for targeted wakeups.
    // JIT owners also have a unique completion alias in this map. Its record is not
    // linked through keyWaitNext: the actual dependency owns those intrusive links.
    std::unordered_map<WaitKey, JobRecord*, WaitKeyHash> waiters_;

    // Counts nonempty dependency lists and JIT owner aliases, not individual sleepers. Presence is read
    // before taking mtx_, so symbol-state publication with no
    // observed waiter avoids the scheduler lock. Hash collisions only cause a locked
    // lookup in the authoritative waiters_ map. Counts change under mtx_ (release);
    // wake() reads them without that lock (acquire).
    // After registration, symbol waits synchronize with the producer's flag RMW;
    // JIT waits recheck completion under its publication mutex. Both handshakes
    // publish the filter to a later producer or observe an earlier completion.
    static constexpr size_t                                 WAITER_FILTER_SHARDS = 4096; // power of two
    std::array<std::atomic<uint32_t>, WAITER_FILTER_SHARDS> waiterFilter_{};

    static size_t waiterShard(const WaitKey& key) noexcept { return WaitKeyHash{}(key) & (WAITER_FILTER_SHARDS - 1); }
    void          filterAdd(const WaitKey& key) noexcept { waiterFilter_[waiterShard(key)].fetch_add(1, std::memory_order_release); }
    void          filterSub(const WaitKey& key) noexcept { waiterFilter_[waiterShard(key)].fetch_sub(1, std::memory_order_release); }

    void bumpClientCountLocked(ClientState& client, int delta);

#if SWC_DEV_MODE
    // Where a parallel build loses its workers: rounds that drain the whole client, sleepers a
    // barrier moves and that park again afterwards, sleepers a dependency wakes precisely,
    // and the share of worker time spent running jobs. Updated under mtx_.
    struct SchedulerStats
    {
        uint64_t barrierRounds   = 0;
        uint64_t barrierWoken    = 0;
        uint64_t barrierReparked = 0;
        uint64_t dependencyWoken = 0;
        uint64_t jobsExecuted    = 0;
        uint64_t busyNs          = 0;
        uint64_t lockWaitNs      = 0; // contended acquisitions of mtx_ on the job paths
        uint64_t poolIdleNs      = 0; // wall time with no job running: serial phases
    };

    void                                  lockCounted(std::unique_lock<std::mutex>& lk);
    void                                  noteActiveWorkersLocked(size_t before);
    void                                  accountStarvationLocked();
    const char*                           setStatsPhase(const char* name);
    std::chrono::steady_clock::time_point poolIdleSince_;

    struct PhaseStats
    {
        const char* name      = nullptr;
        uint64_t    wallNs    = 0;
        uint64_t    serialNs  = 0;
        uint64_t    starvedNs = 0;
    };

    PhaseStats&                           phaseStatsLocked(const char* name);
    std::vector<PhaseStats>               phaseStats_;
    const char*                           statsPhase_ = "other";
    std::chrono::steady_clock::time_point phaseSince_;

    // Per job kind: how much work it does, its longest single job, and the worker time left
    // idle while only jobs of that kind (and others) run and nothing is ready. A long tail of
    // one kind is what keeps a wide pool waiting.
    struct KindStats
    {
        uint64_t jobs      = 0;
        uint64_t busyNs    = 0;
        uint64_t maxNs     = 0;
        uint64_t starvedNs = 0;
        uint32_t running   = 0;
        Utf8     longest;
    };

    static constexpr size_t               NUM_JOB_KINDS = static_cast<size_t>(JobKind::ModuleApiExport) + 1;
    std::array<KindStats, NUM_JOB_KINDS>  kindStats_{};
    std::chrono::steady_clock::time_point lastAccounting_;

    SchedulerStats                        stats_;
    bool                                  statsEnabled_ = false;
    std::chrono::steady_clock::time_point statsStart_;
#endif

    struct RecordPool;
    static JobRecord* allocRecord();
    static void       freeRecord(JobRecord* r);
};

#if SWC_DEV_MODE
#define SWC_SCHED_PHASE_NAME2(__line)      schedPhase##__line
#define SWC_SCHED_PHASE_NAME(__line)       SWC_SCHED_PHASE_NAME2(__line)
#define SWC_SCHED_PHASE(__manager, __name) const JobManager::StatsPhase SWC_SCHED_PHASE_NAME(__LINE__)((__manager), (__name))
#else
#define SWC_SCHED_PHASE(__manager, __name)
#endif

SWC_END_NAMESPACE();
