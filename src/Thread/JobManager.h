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

    void setNumThreads(std::size_t count);
    bool enqueue(const JobRef& job, JobPriority priority);
    bool wake(const JobRef& job);
    void waitAll();

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
    void shutdown() noexcept;
    void workerLoop();

    // Ready queues per priority (store Record* for direct access).
    std::deque<JobRecord*> readyQ_[3];

    // Fast “is work available” counter to avoid CV churn.
    std::atomic<std::uint64_t> readyCount_{0};

    // Running job count (protected by mtx_).
    std::atomic<std::size_t> activeWorkers_{0};

    // Threading & sync
    std::vector<std::thread> workers_;
    mutable std::mutex       mtx_;
    std::condition_variable  cv_;     // work available / shutdown
    std::condition_variable  idleCv_; // becomes idle

    // Lifecycle flags
    std::atomic<bool> accepting_{false};

    // We keep a tiny interface here; implementation detail is in .cpp.
    struct RecordPool;
    static JobRecord* allocRecord(); // may use TLS fast path
    static void       freeRecord(JobRecord* r);
};

SWC_END_NAMESPACE()
