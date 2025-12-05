#pragma once
#include "Thread/Job.h"

SWC_BEGIN_NAMESPACE()

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

    bool enqueue(const JobRef& job, JobPriority priority, JobClientId client = 0);
    bool wake(const JobRef& job);
    bool wakeAll(JobClientId client);
    void waitAll();
    void waitAll(JobClientId client);
    void cancelAll(JobClientId client);

    uint32_t        numWorkers() const noexcept { return static_cast<uint32_t>(workers_.size()); }
    uint32_t        randSeed() const noexcept { return randSeed_; }
    static uint32_t threadIndex() noexcept { return threadIndex_; }

protected:
    friend class Job;
    void notifyDependents(JobRecord* finished);

private:
    // Ready-queue helpers
    void       pushReady(JobRecord* rec, JobPriority priority);
    JobRecord* popReadyLocked();                            // High → Normal → Low
    bool       removeFromReadyQueuesLocked(JobRecord* rec); // returns true if removed & decremented

    // Dependencies
    static bool linkOrSkip(JobRecord* waiter, JobRecord* dep); // returns false if dep already Done

    // Workers
    static JobResult executeJob(const JobRef& job);
    void             workerLoop();

    // Shutdown (private; called only by destructor)
    void shutdown() noexcept;

    // Setup
    const CommandLine*           cmdLine_  = nullptr;
    uint32_t                     randSeed_ = 0;
    static thread_local uint32_t threadIndex_;

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

    // All currently scheduled records (any state except free), to allow cancellation scans.
    std::unordered_set<JobRecord*> liveRecs_;

    // Clients currently under cancellation (block new enqueues; children are dropped)
    std::unordered_set<JobClientId> cancellingClients_;

    // Helpers for client accounting. Callers must hold mtx_.
    void bumpClientCountLocked(JobClientId client, int delta);

    // Cancel a single record and recursively cancel same-client dependents.
    // Assumes mtx_ held. Skips RUNNING/DONE. Returns true if this rec was canceled.
    bool cancelCascadeLocked(JobRecord* rec, JobClientId client);

    // We keep a tiny interface here; implementation detail is in .cpp.
    struct RecordPool;
    static JobRecord* allocRecord(); // may use a TLS fast path
    static void       freeRecord(JobRecord* r);
};

SWC_END_NAMESPACE()
