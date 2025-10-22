#pragma once
#include "Thread/Job.h"

class JobManager
{
public:
    JobManager();
    ~JobManager();

    JobManager(const JobManager&)            = delete;
    JobManager& operator=(const JobManager&) = delete;

    // Configure (or reconfigure) worker threads.
    // If threads already exist, this stops them cleanly and starts a new set.
    void setNumThreads(std::size_t count);

    // Enqueue a job at a given priority. Returns false if:
    //  - not accepting, or
    //  - job is null, or
    //  - job is already enqueued on this manager (job->rec_ != nullptr && job->owner_ == this).
    bool enqueue(const JobRef& job, JobPriority prio);

    // Wake a sleeping job.
    // If it's waiting, it becomes ready immediately.
    // If it's running or already ready, the wake is "armed" so a later Sleep won't park it.
    bool wake(const JobRef& job);

    // Wait until there are no READY or RUNNING jobs left (sleepers are ignored).
    void waitAll();

    // Stop accepting, drain ready/running work, and stop all threads.
    void shutdown() noexcept;

protected:
    friend class Job;
    void notifyDependents(JobRecord* finished); // wake all waiting on 'finished'

private:
    // Ready-queue helpers
    void    pushReady(JobRecord* rec, JobPriority prio);
    JobRecord* popReadyLocked(); // High → Normal → Low

    // Dependencies
    static bool linkOrSkip(JobRecord* waiter, JobRecord* dep); // returns false if dep already Done

    // Workers
    void workerLoop();
    void joinAll() noexcept;
    void clearThreads();

    // Ready queues per priority (store Record* for direct access).
    std::deque<JobRecord*> readyQ_[3];

    // Fast “is work available” counter to avoid CV churn.
    std::atomic<std::uint64_t> readyCount_{0};

    // Running job count (protected by mtx_).
    std::size_t activeWorkers_{0};

    // Threading & sync
    std::vector<std::thread> workers_;
    mutable std::mutex       mtx_;
    std::condition_variable  cv_;     // work available / shutdown
    std::condition_variable  idleCv_; // becomes idle

    // Lifecycle flags
    std::atomic<bool> accepting_{false};
    std::atomic<bool> joined_{false};

    // We keep a tiny interface here; implementation detail is in .cpp.
    struct RecordPool;
    static JobRecord* allocRecord(); // may use TLS fast path
    static void    freeRecord(JobRecord* r);
};
