#pragma once
#include "Thread/Job.h"

SWC_BEGIN_NAMESPACE()

class JobManager
{
public:
    ~JobManager();

    JobManager()                             = default;
    JobManager(const JobManager&)            = delete;
    JobManager& operator=(const JobManager&) = delete;

    // Configure worker threads.
    void setNumThreads(std::size_t count);

    // Enqueue a job at a given priority for a given client. Returns false if:
    //  - not accepting, or
    //  - job is null, or
    //  - job is already enqueued on this manager (job->rec_ != nullptr && job->owner_ == this), or
    //  - the client is currently being cancelled (see cancelAll()).
    bool enqueue(const JobRef& job, JobPriority priority, JobClientId client = 0);

    // Wake a sleeping job.
    // If it's waiting, it becomes ready immediately.
    // If it's running or already ready, the wake is "armed" so a later Sleep won't park it.
    bool wake(const JobRef& job);

    // Wait until there are no READY or RUNNING jobs left (sleepers are ignored).
    void waitAll();

    // Wait until there are no READY or RUNNING jobs left for 'client' (sleepers are ignored).
    void waitAll(JobClientId client);

    // Cancel all **pending** jobs (READY or WAITING) for 'client',
    // block new enqueues for that client, then wait for any RUNNING jobs
    // of that client to finish. When this returns, the client has no jobs
    // in READY/RUNNING/WAITING.
    void cancelAll(JobClientId client);

    // Generate a new unique client ID (thread-safe).
    JobClientId newClientId();

    uint32_t numWorkers() const noexcept { return static_cast<uint32_t>(workers_.size()); }

protected:
    friend class Job;
    void notifyDependents(JobRecord* finished); // wake all waiting on 'finished'

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
