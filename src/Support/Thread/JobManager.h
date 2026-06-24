#pragma once
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

using JobClientId = uint32_t;

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

    // Shared wake target for every job parked on SemaWaitTypeInfoGeneration. Type-info
    // generation contention is not keyable to a single producer (any worker publishing a
    // type-info can unblock any waiter), so all such waiters register on this one sentinel
    // and a type-info publication wakes them all via wakeTypeInfoGeneration().
    static const void* typeInfoGenWaitTarget();
    void               wakeTypeInfoGeneration();

    bool wakeAll(JobClientId client);
    void waitAll();
    void waitAll(JobClientId client);

    uint32_t      numWorkers() const noexcept { return static_cast<uint32_t>(workers_.size()); }
    uint32_t      randSeed() const noexcept { return randSeed_; }
    static size_t threadIndex() noexcept { return threadIndex_; }
    bool          isSingleThreaded() const noexcept { return singleThreaded_; }

private:
    void       pushReady(JobRecord* rec, JobPriority priority);
    JobRecord* popReadyLocked();
    JobRecord* popReadyAndMarkRunningLocked();
    JobRecord* popReadyForClientLocked(JobClientId client);
    bool       isDrainedLocked() const;

    static JobResult              executeJob(Job& job);
    void                          handleJobResult(JobRecord* rec, JobResult res);
    void                          workerLoop();
    static std::optional<WaitKey> computeWaitKey(const Job& job);
    void                          unregisterWaiterLocked(JobRecord* rec);

    void shutdown() noexcept;

    // Setup
    bool                       singleThreaded_ = false;
    const CommandLine*         cmdLine_        = nullptr;
    uint32_t                   randSeed_       = 0;
    static thread_local size_t threadIndex_;

    // Ready queues per priority (store Record* for direct access).
    std::deque<JobRecord*> readyQ_[3];

    // Fast “is work available” counter to avoid CV churn.
    std::atomic<std::uint64_t> readyCount_{0};

    // Running job count.
    std::atomic<std::size_t> activeWorkers_{0};

    // Threading & sync
    std::vector<std::thread> workers_;
    mutable std::mutex       mtx_;
    std::condition_variable  cv_;     // work available / shutdown
    std::condition_variable  idleCv_; // becomes idle (global or per-client)

    // Lifecycle flags
    std::atomic<bool> accepting_{false};
    std::atomic<bool> joined_{false};

    // Per-client READY/RUNNING counters (protected by mtx_)
    std::atomic<JobClientId>                     nextClientId_{1}; // start at 1, 0 reserved as "default client"
    std::unordered_map<JobClientId, std::size_t> clientReadyRunning_;
    std::atomic<uint32_t>                        nextIndex_{0};

    // All currently scheduled records (any state except free), to allow wakeAll scans.
    std::unordered_set<JobRecord*> liveRecs_;

    // Sleeping jobs indexed by the exact dependency they wait on, for targeted wakeups.
    // Only keyable sleepers appear here; non-keyable ones stay wildcard (barrier-woken).
    std::unordered_multimap<WaitKey, JobRecord*, WaitKeyHash> waiters_;

    // Lock-free presence filter over the registered wait keys. wake() consults it BEFORE
    // taking mtx_: an empty shard proves no job is parked on the key, so the (overwhelmingly
    // common) wake with no waiter never touches the global scheduler mutex. Symbol-state wakes
    // (setTyped/setDeclared/...) fire on every symbol transition across the whole compile; the
    // old unconditional lock serialized every worker on mtx_ even though almost nobody waits on
    // that exact symbol. The filter is a counting filter: shard == 0 means "no waiter here",
    // shard > 0 means "maybe a waiter" (hash collisions only cause a correct fall-through to the
    // authoritative locked scan). A genuinely lost wake is impossible beyond the pre-existing
    // best-effort window already covered by the wakeAll barrier in Sema::waitDone. All mutations
    // happen under mtx_ (release); only wake()'s fast-path read is lock-free (acquire).
    static constexpr size_t                                 WAITER_FILTER_SHARDS = 4096; // power of two
    std::array<std::atomic<uint32_t>, WAITER_FILTER_SHARDS> waiterFilter_{};

    static size_t waiterShard(const WaitKey& key) noexcept { return WaitKeyHash{}(key) & (WAITER_FILTER_SHARDS - 1); }
    void          filterAdd(const WaitKey& key) noexcept { waiterFilter_[waiterShard(key)].fetch_add(1, std::memory_order_release); }
    void          filterSub(const WaitKey& key) noexcept { waiterFilter_[waiterShard(key)].fetch_sub(1, std::memory_order_release); }

    void bumpClientCountLocked(JobClientId client, int delta);

    struct RecordPool;
    static JobRecord* allocRecord();
    static void       freeRecord(JobRecord* r);
};

SWC_END_NAMESPACE();
