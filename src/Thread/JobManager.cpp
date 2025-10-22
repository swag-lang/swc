#include "pch.h"

#include "Thread/JobManager.h"

struct JobManager::RecordPool
{
    // Thread-local free list (LIFO for cache locality).
    static thread_local std::vector<JobRecord*> tls;

    // Global fallback (small), guarded by a mutex.
    static std::mutex              gMutex;
    static std::vector<JobRecord*> gFree;
    static constexpr std::size_t   K_TLS_MAX = 1024; // cap per thread to avoid unbounded growth
};

thread_local std::vector<JobRecord*> JobManager::RecordPool::tls;
std::mutex                           JobManager::RecordPool::gMutex;
std::vector<JobRecord*>              JobManager::RecordPool::gFree;

JobRecord* JobManager::allocRecord()
{
    // Fast path: thread-local
    auto& v = RecordPool::tls;
    if (!v.empty())
    {
        JobRecord* r = v.back();
        v.pop_back();
        return r;
    }

    // Slow path: global pool
    std::lock_guard lk(RecordPool::gMutex);
    if (!RecordPool::gFree.empty())
    {
        JobRecord* r = RecordPool::gFree.back();
        RecordPool::gFree.pop_back();
        return r;
    }

    // Fallback: heap
    return new JobRecord();
}

void JobManager::freeRecord(JobRecord* r)
{
    if (!r)
        return;

    // Minimal reset (fields set on reuse anyway). Clear heavy stuff here.
    r->job.reset();
    r->dependents.clear();
    r->wakeGen.store(0, std::memory_order_relaxed);
    r->state = JobRecord::State::Ready;
    r->prio  = JobPriority::Normal;

    // Try to return to TLS; spill to global if TLS is full.
    auto& v = RecordPool::tls;
    if (v.size() < RecordPool::K_TLS_MAX)
    {
        v.push_back(r);
        return;
    }
    std::lock_guard lk(RecordPool::gMutex);
    RecordPool::gFree.push_back(r);
}

JobManager::~JobManager()
{
    shutdown();
}

void JobManager::setNumThreads(std::size_t count)
{
    SWAG_ASSERT(workers_.empty());

    if (count == 0)
        count = std::thread::hardware_concurrency();

    accepting_ = true;
    joined_    = false;
    workers_.reserve(count);
    for (std::size_t i = 0; i < count; ++i)
        workers_.emplace_back([this] { workerLoop(); });
}

bool JobManager::enqueue(const JobRef& job, JobPriority priority)
{
    if (!job)
        return false;

    std::unique_lock lk(mtx_);
    if (!accepting_)
        return false;

    // If already scheduled on this manager, refuse (simplifies invariants).
    if (job->owner_ == this && job->rec_ != nullptr)
        return false;

    // Acquire a Record from the pool and wire it up.
    JobRecord* rec = allocRecord();
    rec->job       = job; // keep job alive while scheduled
    rec->prio      = priority;
    rec->state     = JobRecord::State::Ready;
    rec->dependents.clear();
    rec->wakeGen.store(0, std::memory_order_relaxed);

    job->owner_ = this;
    job->rec_   = rec;

    pushReady(rec, priority);
    cv_.notify_one();
    return true;
}

bool JobManager::wake(const JobRef& job)
{
    if (!job)
        return false;

    std::unique_lock lk(mtx_);
    // If not scheduled on this manager (or already completed), ignore.
    if (job->owner_ != this || job->rec_ == nullptr)
        return false;

    JobRecord* rec = job->rec_;

    // Arm against a lost-wake during a run.
    ++rec->wakeGen;

    if (rec->state == JobRecord::State::Waiting)
    {
        rec->state = JobRecord::State::Ready;
        pushReady(rec, rec->prio);
        cv_.notify_one();
    }

    return true;
}

void JobManager::waitAll()
{
    std::unique_lock lk(mtx_);
    idleCv_.wait(lk, [this] {
        return readyCount_.load(std::memory_order_acquire) == 0 && activeWorkers_ == 0;
    });
}

void JobManager::shutdown() noexcept
{
    {
        std::unique_lock lk(mtx_);
        if (joined_)
            return;
        accepting_ = false;
        cv_.notify_all();
    }

    joinAll();
    // NOTE: User code still owns remaining sleepers (if any).
    // They are not runnable; their rec_ remains set until they are complete or are canceled.
}

void JobManager::pushReady(JobRecord* rec, JobPriority priority)
{
    readyQ_[static_cast<int>(priority)].push_back(rec);
    readyCount_.fetch_add(1, std::memory_order_release);
}

// Link waiter to dep; returns false if dep already Done (no parking needed).
bool JobManager::linkOrSkip(JobRecord* waiter, JobRecord* dep)
{
    if (!dep || dep->state == JobRecord::State::Done)
        return false;
    dep->dependents.push_back(waiter->job.get()); // store Job* for the waiter
    waiter->state = JobRecord::State::Waiting;
    return true;
}

// Wake everyone waiting on 'finished'.
// We copy out the vector (move) to minimize lock hold time and avoid reentrancy pitfalls.
void JobManager::notifyDependents(JobRecord* finished)
{
    const auto deps = std::move(finished->dependents);
    finished->dependents.clear();

    for (const Job* job : deps)
    {
        // If the waiter is still scheduled here, it must have non-null 'rec_'.
        if (job && job->owner_ == this && job->rec_)
        {
            JobRecord* rec = job->rec_;
            ++rec->wakeGen; // make future Sleep a no-op (requeue)
            if (rec->state == JobRecord::State::Waiting)
            {
                rec->state = JobRecord::State::Ready;
                pushReady(rec, rec->prio);
            }
        }
    }

    if (!deps.empty())
        cv_.notify_all();
}

// Favor High: Normal: Low. Caller must hold 'mtx_'.
JobRecord* JobManager::popReadyLocked()
{
    for (auto& q : readyQ_)
    {
        if (!q.empty())
        {
            JobRecord* rec = q.front();
            q.pop_front();
            readyCount_.fetch_sub(1, std::memory_order_acq_rel);
            return rec;
        }
    }

    return nullptr;
}

void JobManager::workerLoop()
{
    auto popReadyAndMarkRunningLocked = [this]() -> JobRecord* {
        JobRecord* rec = popReadyLocked();
        if (!rec)
            return nullptr;

        if (rec->state == JobRecord::State::Done) // defensive; should rarely happen
            return nullptr;

        rec->state = JobRecord::State::Running;
        ++activeWorkers_;
        return rec;
    };

    auto maybeExitIfDrainedLocked = [this]() -> bool {
        if (!accepting_ && readyCount_.load(std::memory_order_acquire) == 0)
            return true;
        return false;
    };

    for (;;)
    {
        JobRecord* rec = nullptr;

        // Fast path: brief spin/yield if no ready work
        int spins = 0;
        while (readyCount_.load(std::memory_order_acquire) == 0 && accepting_)
        {
            // Small spin to avoid CV storms for micro-jobs under bursts.
            constexpr int spinMax = 200;
            if (++spins < spinMax)
            {
                std::this_thread::yield();
                continue;
            }

            // Slow path: fall back to CV wait
            {
                std::unique_lock lk(mtx_);
                cv_.wait(lk, [this] {
                    return readyCount_.load(std::memory_order_acquire) > 0 || !accepting_;
                });

                if (maybeExitIfDrainedLocked())
                    return;
                rec = popReadyAndMarkRunningLocked();
            }

            // leave the spin loop (either with a job or to try fast pop)
            break;
        }

        // If the spin loop did not acquire a job yet, but we observed ready work, do a short locked pop.
        if (!rec)
        {
            std::unique_lock lk(mtx_);
            if (maybeExitIfDrainedLocked())
                return;
            rec = popReadyAndMarkRunningLocked();
        }

        if (!rec)
            continue;

        // From here on, we’re an active worker for this job.
        struct ActiveGuard
        {
            size_t*                  ref;
            std::atomic<uint64_t>*   ready;
            std::condition_variable* idleCv;
            ~ActiveGuard()
            {
                if (--*ref == 0 && ready->load(std::memory_order_acquire) == 0)
                    idleCv->notify_all();
            }
        };

        ActiveGuard activeGuard{.ref = &activeWorkers_, .ready = &readyCount_, .idleCv = &idleCv_};

        // Snapshot wake ticket at the start for lost-wake prevention on Sleep.
        const auto wakeAtStart = rec->wakeGen.load(std::memory_order_acquire);

        // Execute job
        JobResult res;
        try
        {
            res = rec->job->process();
        }
        catch (...)
        {
            res = JobResult::Done;
        }

        // Completion / state transition handling
        {
            std::unique_lock lk(mtx_);

            const bool lostWakePrevented = (res == JobResult::Sleep) && (rec->wakeGen.load(std::memory_order_acquire) != wakeAtStart);

            switch (res)
            {
                case JobResult::Done:
                {
                    rec->state = JobRecord::State::Done;
                    notifyDependents(rec);
                    rec->job->rec_   = nullptr;
                    rec->job->owner_ = nullptr;
                    freeRecord(rec);
                    break;
                }

                case JobResult::Sleep:
                {
                    if (lostWakePrevented)
                    {
                        // Someone called wake() while we were running: keep runnable.
                        rec->state = JobRecord::State::Ready;
                        pushReady(rec, rec->prio);
                        cv_.notify_one();
                    }
                    else
                    {
                        rec->state = JobRecord::State::Waiting;
                    }
                    rec->job->clearIntents(); // consume any stale intent
                    break;
                }

                case JobResult::SleepOn:
                {
                    JobRecord* depRec = nullptr;
                    if (rec->job->dep_ && rec->job->dep_->owner_ == this)
                        depRec = rec->job->dep_->rec_;

                    if (!depRec || !linkOrSkip(rec, depRec))
                    {
                        // dependency already done/unknown: keep runnable
                        rec->state = JobRecord::State::Ready;
                        pushReady(rec, rec->prio);
                        cv_.notify_one();
                    }

                    rec->job->clearIntents();
                    break;
                }

                case JobResult::SpawnAndSleep:
                {
                    // Create or reuse child's record and enqueue.
                    JobRecord* childRec = nullptr;
                    if (rec->job->child_)
                    {
                        if (rec->job->child_->owner_ != this || rec->job->child_->rec_ == nullptr)
                        {
                            JobRecord* r = allocRecord();
                            r->job       = rec->job->child_;
                            r->prio      = rec->job->childPriority_;
                            r->state     = JobRecord::State::Ready;
                            r->dependents.clear();
                            r->wakeGen.store(0, std::memory_order_relaxed);

                            rec->job->child_->owner_ = this;
                            rec->job->child_->rec_   = r;
                            childRec                 = r;
                        }
                        else
                        {
                            // Already enqueued on this manager; treat as dependency only.
                            childRec = rec->job->child_->rec_;
                        }
                    }

                    const bool parked = childRec && linkOrSkip(rec, childRec);
                    if (childRec)
                    {
                        pushReady(childRec, childRec->prio);
                        cv_.notify_one();
                    }

                    if (!parked)
                    {
                        // Parent stays runnable.
                        rec->state = JobRecord::State::Ready;
                        pushReady(rec, rec->prio);
                        cv_.notify_one();
                    }

                    rec->job->clearIntents();
                    break;
                }
            }
        }
    }
}

void JobManager::joinAll() noexcept
{
    if (joined_)
        return;
    
    for (auto& t : workers_)
    {
        if (t.joinable())
        {
            t.join();
        }
    }
    
    joined_ = true;
}

void JobManager::clearThreads()
{
    workers_.clear();
}
