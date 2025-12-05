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

    bool enqueue(Job& job, JobPriority priority, JobClientId client = 0);
    bool wakeAll(JobClientId client);
    void waitAll();
    void waitAll(JobClientId client);

    uint32_t      numWorkers() const noexcept { return static_cast<uint32_t>(workers_.size()); }
    uint32_t      randSeed() const noexcept { return randSeed_; }
    static size_t threadIndex() noexcept { return threadIndex_; }

private:
    void       pushReady(JobRecord* rec, JobPriority priority);
    JobRecord* popReadyLocked(); // High → Normal → Low

    static JobResult executeJob(const Job& job);
    void             handleJobResult(JobRecord* rec, JobResult res);
    void             workerLoop();

    void shutdown() noexcept;

    // Setup
    const CommandLine*         cmdLine_  = nullptr;
    uint32_t                   randSeed_ = 0;
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

    // All currently scheduled records (any state except free), to allow wakeAll scans.
    std::unordered_set<JobRecord*> liveRecs_;

    void bumpClientCountLocked(JobClientId client, int delta);

    struct RecordPool;
    static JobRecord* allocRecord();
    static void       freeRecord(JobRecord* r);
};

SWC_END_NAMESPACE()
