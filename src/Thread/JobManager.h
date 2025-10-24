#pragma once
#include "Thread/Job.h"

SWC_BEGIN_NAMESPACE()

class JobManager
{
public:
    using ClientId = std::uint64_t;

    ~JobManager();

    JobManager()                             = default;
    JobManager(const JobManager&)            = delete;
    JobManager& operator=(const JobManager&) = delete;

    // Configure (or reconfigure) worker threads.
    // If threads already exist, this stops them cleanly and starts a new set.
    void setNumThreads(std::size_t count);

    // Enqueue a job at a given priority for a given client. Returns false if:
    //  - not accepting, or
    //  - job is null, or
    //  - job is already enqueued on this manager (job->rec_ != nullptr && job->owner_ == this).
    bool enqueue(const JobRef& job, JobPriority priority, ClientId client);

    // Convenience overload: client 0 is the default client.
    bool enqueue(const JobRef& job, JobPriority priority) { return enqueue(job, priority, 0); }

    // Wake a sleeping job.
    // If it's waiting, it becomes ready immediately.
    // If it's running or already ready, the wake is "armed" so a later Sleep won't park it.
    bool wake(const JobRef& job);

    // Wait until there are no READY or RUNNING jobs left (sleepers are ignored).
    void waitAll();

    // Wait until there are no READY or RUNNING jobs left for 'client' (sleepers are ignored).
    void waitAll(ClientId client);

    // Stop accepting, drain ready/running work, and stop all threads.
    void shutdown() noexcept;

    uint32_t numWorkers() const noexcept { return static_cast<uint32_t>(workers_.size()); }

protected:
    friend class Job;
    void notifyDependents(JobRecord* finished); // wake all waiting on 'finished'

private:
    // Ready-queue helpers
    void       pushReady(JobRecord* rec, JobPriority priority);
    JobRecord* popReadyLocked(); // High → Normal → Low

    // Dependencies
    static bool linkOrSkip(JobRecord* waiter, JobRecord* dep); // returns false if dep already Done

    // Workers
    void workerLoop();
    void joinAll() noexcept;
    void clearThreads();

    // Priority index mapping (stable even if enum values change)
    static int prioToIndex(JobPriority p) noexcept;

    // Ready queues per priority (store Record* for direct access).
    // Indexing is High (0), Normal (1), Low (2) via prioToIndex().
    std::deque<JobRecord*> readyQ_[3];

    // Fast “is work available” counter to avoid CV churn.
    std::atomic<std::uint64_t> readyCount_{0};

    // Running job count (protected by mtx_).
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
    std::unordered_map<ClientId, std::size_t> clientReadyRunning_;

    // Mapping from JobRecord* to ClientId (protected by mtx_).
    // This avoids modifying JobRecord in Job.h.
    std::unordered_map<JobRecord*, ClientId> recClient_;

    // Helpers for client accounting. Callers must hold mtx_.
    void     bumpClientCountLocked(ClientId client, int delta);
    ClientId clientOfLocked(JobRecord* rec) const;

    // We keep a tiny interface here; implementation detail is in .cpp.
    struct RecordPool;
    static JobRecord* allocRecord(); // may use TLS fast path
    static void       freeRecord(JobRecord* r);
};

SWC_END_NAMESPACE()
