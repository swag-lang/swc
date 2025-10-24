#include "pch.h"
#include "Thread/JobManager.h"

#include <algorithm>

SWC_BEGIN_NAMESPACE()

//==============================
// Record pool (unchanged shape)
//==============================
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
    // NOTE: client is tracked in JobManager::recClient_, not on JobRecord.

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

//==============================

JobManager::~JobManager()
{
    shutdown();
}

int JobManager::prioToIndex(JobPriority p) noexcept
{
    // Stable mapping regardless of enum underlying values.
    switch (p)
    {
        case JobPriority::High:
            return 0;
        case JobPriority::Normal:
            return 1;
        case JobPriority::Low:
            return 2;
        default:
            return 1;
    }
}

void JobManager::setNumThreads(std::size_t count)
{
    // If already running, stop them cleanly first.
    if (!workers_.empty())
    {
        shutdown();     // stop & join current workers
        clearThreads(); // drop joined thread objects
    }

    if (count == 0)
        count = std::thread::hardware_concurrency();

    accepting_ = true;
    joined_    = false;
    workers_.reserve(count);
    for (std::size_t i = 0; i < count; ++i)
        workers_.emplace_back([this] { workerLoop(); });
}

bool JobManager::enqueue(const JobRef& job, JobPriority priority, ClientId client)
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

    // Associate record with its client (side map).
    recClient_[rec] = client;

    job->owner_ = this;
    job->rec_   = rec;

    bumpClientCountLocked(client, +1); // READY enters counted set
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
    rec->wakeGen.fetch_add(1, std::memory_order_acq_rel);

    if (rec->state == JobRecord::State::Waiting)
    {
        rec->state = JobRecord::State::Ready;
        bumpClientCountLocked(clientOfLocked(rec), +1); // WAITING -> READY enters counted set
        pushReady(rec, rec->prio);
        cv_.notify_one();
    }

    return true;
}

void JobManager::waitAll()
{
    std::unique_lock lk(mtx_);
    idleCv_.wait(lk, [this] {
        return readyCount_.load(std::memory_order_acquire) == 0 &&
               activeWorkers_.load(std::memory_order_acquire) == 0;
    });
}

void JobManager::waitAll(ClientId client)
{
    std::unique_lock lk(mtx_);
    idleCv_.wait(lk, [this, client] {
        auto              it = clientReadyRunning_.find(client);
        const std::size_t n  = (it == clientReadyRunning_.end()) ? 0 : it->second;
        return n == 0;
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
    clearThreads(); // drop joined threads

    // NOTE: User code still owns remaining sleepers (if any).
    // They are not runnable; their rec_ remains set until they are complete or are canceled.
}

void JobManager::pushReady(JobRecord* rec, JobPriority priority)
{
    readyQ_[prioToIndex(priority)].push_back(rec);
    readyCount_.fetch_add(1, std::memory_order_release);
}

// Link waiter to dep; returns false if dep already Done (no parking needed).
bool JobManager::linkOrSkip(JobRecord* waiter, JobRecord* dep)
{
    if (!dep || dep->state == JobRecord::State::Done)
        return false;
    waiter->state = JobRecord::State::Waiting;
    dep->dependents.push_back(waiter->job.get()); // store Job* for the waiter
    return true;
}

// Wake everyone waiting on 'finished'.
// NOTE: This function is called with mtx_ held by the caller.
// We keep the lock while we move and requeue to keep things simple and avoid reentrancy.
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
            rec->wakeGen.fetch_add(1, std::memory_order_acq_rel); // prevent lost-wake
            if (rec->state == JobRecord::State::Waiting)
            {
                rec->state = JobRecord::State::Ready;
                bumpClientCountLocked(clientOfLocked(rec), +1); // WAITING -> READY
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
    static constexpr int order[] = {0, 1, 2}; // High(0) -> Normal(1) -> Low(2)
    for (int idx : order)
    {
        auto& q = readyQ_[idx];
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
        activeWorkers_.fetch_add(1, std::memory_order_acq_rel);
        return rec;
    };

    auto maybeExitIfDrainedLocked = [this]() -> bool {
        // Once we stop accepting, threads should exit as soon as the READY queues are empty.
        // A currently-running worker will finish and either requeue or also exit.
        return !accepting_ && readyCount_.load(std::memory_order_acquire) == 0;
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
            std::atomic<size_t>*     ref;
            std::atomic<uint64_t>*   ready;
            std::condition_variable* idleCv;
            ~ActiveGuard()
            {
                // Notify global idle waiters when the last active worker finishes
                // and there is no ready work left.
                if (ref->fetch_sub(1, std::memory_order_acq_rel) == 1 &&
                    ready->load(std::memory_order_acquire) == 0)
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

            const bool lostWakePrevented =
            (res == JobResult::Sleep) &&
            (rec->wakeGen.load(std::memory_order_acquire) != wakeAtStart);

            const ClientId c = clientOfLocked(rec);

            switch (res)
            {
                case JobResult::Done:
                {
                    rec->state = JobRecord::State::Done;
                    notifyDependents(rec);

                    // RUNNING leaves the counted set.
                    bumpClientCountLocked(c, -1);

                    // Detach and recycle
                    rec->job->rec_   = nullptr;
                    rec->job->owner_ = nullptr;
                    recClient_.erase(rec);
                    freeRecord(rec);
                    break;
                }

                case JobResult::Sleep:
                {
                    if (lostWakePrevented)
                    {
                        // Someone called wake() while we were running: keep runnable.
                        rec->state = JobRecord::State::Ready;
                        // Still in counted set (READY/RUNNING), no bump.
                        pushReady(rec, rec->prio);
                        cv_.notify_one();
                    }
                    else
                    {
                        // Park: RUNNING -> WAITING leaves the counted set.
                        rec->state = JobRecord::State::Waiting;
                        bumpClientCountLocked(c, -1);
                    }
                    rec->job->clearIntents(); // consume any stale intent
                    break;
                }

                case JobResult::SleepOn:
                {
                    JobRecord* depRec = nullptr;
                    if (rec->job->dep_ && rec->job->dep_->owner_ == this)
                        depRec = rec->job->dep_->rec_;

                    if (depRec && linkOrSkip(rec, depRec))
                    {
                        // Parked on dependency: RUNNING -> WAITING leaves counted set.
                        rec->state = JobRecord::State::Waiting;
                        bumpClientCountLocked(c, -1);
                    }
                    else
                    {
                        // Dependency already done/unknown: keep runnable (still counted)
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

                            childRec = r;

                            // Inherit parent's client by default.
                            const ClientId childClient = c;
                            recClient_[childRec]       = childClient;

                            // Child READY enters counted set.
                            bumpClientCountLocked(childClient, +1);
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
                        // Parent stays runnable (still counted).
                        rec->state = JobRecord::State::Ready;
                        pushReady(rec, rec->prio);
                        cv_.notify_one();
                    }
                    else
                    {
                        // Parent parked: RUNNING -> WAITING leaves counted set.
                        rec->state = JobRecord::State::Waiting;
                        bumpClientCountLocked(c, -1);
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
    // Only clear after joining to avoid UB.
    // (In debug you could assert(joined_) here.)
    workers_.clear();
}

//==============================
// Client helpers
//==============================

void JobManager::bumpClientCountLocked(ClientId client, int delta)
{
    auto& c = clientReadyRunning_[client];
    // Simple saturating behavior is not required; invariants preserve correctness.
    c = static_cast<std::size_t>(static_cast<long long>(c) + delta);
    if (c == 0)
    {
        // Someone may be waiting for this client.
        idleCv_.notify_all();
    }
}

JobManager::ClientId JobManager::clientOfLocked(JobRecord* rec) const
{
    auto it = recClient_.find(rec);
    return (it == recClient_.end()) ? ClientId{0} : it->second;
}

SWC_END_NAMESPACE()
