#pragma once

/*
    JobManager — ultra-light scheduler for lots of tiny jobs

    What’s special here:
      • No per-enqueue heap allocation for scheduler state: Records come from a recycled pool.
      • No map lookups: each Job keeps a pointer to its own Record (rec_).
      • Three FIFO ready queues: High, Normal, Low.
      • Tiny critical sections; job code runs outside the mutex.
      • “Lost wake” race is handled via a wake ticket (wakeGen).

    Programming model:
      • Derive from Job and implement process().
      • process() returns Result (Done, Sleep, SleepOn, SpawnAndSleep).
      • If you return SleepOn / SpawnAndSleep, set dependency / child in your job object before returning.
      • A job can wake any dependents early via wakeDependents().
*/

class JobManager
{
public:
    class Job;

    using JobRef = std::shared_ptr<Job>;

    enum class Priority : std::uint8_t
    {
        High   = 0,
        Normal = 1,
        Low    = 2
    };

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
    bool enqueue(const JobRef& job, Priority prio);

    // Wake a sleeping job.
    // If it's waiting, it becomes ready immediately.
    // If it's running or already ready, the wake is "armed" so a later Sleep won't park it.
    bool wake(const JobRef& job);

    // Wait until there are no READY or RUNNING jobs left (sleepers are ignored).
    void waitAll();

    // Stop accepting, drain ready/running work, and stop all threads.
    void shutdown() noexcept;

private:
    // Internal scheduler state for a job (kept small, cache-friendly).
    struct Record
    {
        // Keep the job alive while scheduled (the user may drop their last ref).
        JobRef job;

        Priority prio{Priority::Normal};

        enum class State : std::uint8_t
        {
            Ready,
            Running,
            Waiting,
            Done
        };
        State state{State::Ready};

        // "Wake ticket" to prevent lost-wake races.
        // If a wake() occurs while the job is running, a following Sleep will NOT park it.
        std::atomic<std::uint64_t> wakeGen{0};

        // Jobs currently waiting for this job to complete (stored as Job*).
        // We look up their Record via job->rec_ under the manager lock.
        std::vector<Job*> dependents;
    };

    // Ready-queue helpers
    void    pushReady(Record* rec, Priority prio);
    Record* popReadyLocked(); // High → Normal → Low

    // Dependencies
    bool linkOrSkip(Record* waiter, Record* dep); // returns false if dep already Done
    void notifyDependents(Record* finished);      // wake all waiting on 'finished'

    // Workers
    void workerLoop();
    void joinAll() noexcept;
    void clearThreads();

    // Ready queues per priority (store Record* for direct access).
    std::deque<Record*> readyQ_[3];

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
    static Record* allocRecord(); // may use TLS fast path
    static void    freeRecord(Record* r);
};

// =======================================================================
//                                  Job
// =======================================================================

class JobManager::Job : public std::enable_shared_from_this<Job>
{
    friend class JobManager;

public:
    // What the manager should do after process().
    enum class Result : std::uint8_t
    {
        Done,         // finished; remove and wake dependents
        Sleep,        // pause until woken via JobManager::wake(job)
        SleepOn,      // sleep until dep_ completes (set via setDependency / sleepOn)
        SpawnAndSleep // enqueue child_ (at childPriority_) and sleep until it completes
    };

    virtual ~Job() = default;

    // Write your work here. Return a Result.
    // If returning SleepOn / SpawnAndSleep, be sure to set intent in 'this' before returning.
    virtual Result process() = 0;

    // Wake all jobs currently waiting on this job (even before finishing).
    void wakeDependents();

protected:
    // Intent setters (used before returning from process()):

    // For Result::SleepOn
    void setDependency(const JobRef& dep) { dep_ = dep; }

    // For Result::SpawnAndSleep
    void setChildAndPriority(const JobRef& child, Priority prio)
    {
        child_         = child;
        childPriority_ = prio;
    }

    // Convenience shorthands
    Result sleep()
    {
        clearIntents();
        return Result::Sleep;
    }
    Result sleepOn(const JobRef& dep)
    {
        dep_ = dep;
        return Result::SleepOn;
    }
    Result spawnAndSleep(const JobRef& child, Priority prio)
    {
        child_         = child;
        childPriority_ = prio;
        return Result::SpawnAndSleep;
    }

private:
    // Back-pointers / scheduler hooks (manager-owned, but stored on the job)
    JobManager* owner_{nullptr}; // which manager, if any, owns this job right now
    Record*     rec_{nullptr};   // scheduler state for THIS manager run (from the pool)

    // User intent (read by manager under lock after process()):
    JobRef   dep_;   // dependency for SleepOn
    JobRef   child_; // child for SpawnAndSleep
    Priority childPriority_{Priority::Normal};

    // Cleared by manager after consuming intent.
    void clearIntents()
    {
        dep_.reset();
        child_.reset();
        childPriority_ = Priority::Normal;
    }
};
