#include "pch.h"
#include "Thread/JobManager.h"

#include <algorithm>

SWC_BEGIN_NAMESPACE()

//==============================
// Record pool
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
    r->state    = JobRecord::State::Ready;
    r->priority = JobPriority::Normal;
    r->client   = 0;

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

void JobManager::setNumThreads(std::size_t count)
{
    // One-shot only.
    SWAG_ASSERT(workers_.empty());
    SWAG_ASSERT(!accepting_);

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

    if (cancellingClients_.contains(client))
        return false;

    // If already scheduled on this manager, refuse (simplifies invariants).
    if (job->owner_ == this && job->rec_ != nullptr)
        return false;

    // Acquire a Record from the pool and wire it up.
    JobRecord* rec = allocRecord();
    rec->job       = job; // keep job alive while scheduled
    rec->priority  = priority;
    rec->client    = client;
    rec->state     = JobRecord::State::Ready;
    rec->dependents.clear();
    rec->wakeGen.store(0, std::memory_order_relaxed);

    job->owner_ = this;
    job->rec_   = rec;

    liveRecs_.insert(rec);
    bumpClientCountLocked(client, +1); // READY enters a counted set
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
        bumpClientCountLocked(rec->client, +1); // WAITING -> READY enters a counted set
        pushReady(rec, rec->priority);
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
        const auto        it = clientReadyRunning_.find(client);
        const std::size_t n  = (it == clientReadyRunning_.end()) ? 0 : it->second;
        return n == 0;
    });
}

void JobManager::cancelAll(ClientId client)
{
    std::unique_lock lk(mtx_);

    // Block new enqueues and drop any future spawned children for this client.
    cancellingClients_.insert(client);

    // Cancel all current non-running jobs of this client (READY & WAITING) and
    // recursively cancel same-client dependents to avoid wake/requeue churn.
    // We work on a snapshot because cancel mutates liveRecs_.
    std::vector<JobRecord*> snapshot;
    snapshot.reserve(liveRecs_.size());
    for (JobRecord* r : liveRecs_)
        snapshot.push_back(r);

    for (JobRecord* r : snapshot)
    {
        if (!r)
            continue;
        if (r->client != client)
            continue;
        if (r->state == JobRecord::State::Running || r->state == JobRecord::State::Done)
            continue;

        cancelCascadeLocked(r, client);
    }

    // Now wait for the client's RUNNING jobs to drain. Because we block new enqueues and
    // cancel children spawned in SpawnAndSleep (see workerLoop), the count will reach zero.
    idleCv_.wait(lk, [this, client] {
        const auto        it = clientReadyRunning_.find(client);
        const std::size_t n  = (it == clientReadyRunning_.end()) ? 0 : it->second;
        return n == 0;
    });

    // Unblock the client for future work.
    cancellingClients_.erase(client);
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

    for (auto& t : workers_)
    {
        if (t.joinable())
            t.join();
    }
    workers_.clear();
    joined_ = true;

    // NOTE: User code still owns remaining sleepers (if any).
    // They are not runnable; their rec_ remains set until they are complete or are canceled.
}

void JobManager::pushReady(JobRecord* rec, JobPriority priority)
{
    readyQ_[static_cast<int>(priority)].push_back(rec);
    readyCount_.fetch_add(1, std::memory_order_release);
}

// Remove a specific record from the ready queues (if present).
bool JobManager::removeFromReadyQueuesLocked(JobRecord* rec)
{
    const int idx = static_cast<int>(rec->priority);
    auto&     q   = readyQ_[idx];
    for (auto it = q.begin(); it != q.end(); ++it)
    {
        if (*it == rec)
        {
            q.erase(it);
            readyCount_.fetch_sub(1, std::memory_order_acq_rel);
            return true;
        }
    }
    return false;
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
                bumpClientCountLocked(rec->client, +1); // WAITING -> READY
                pushReady(rec, rec->priority);
            }
        }
    }

    if (!deps.empty())
        cv_.notify_all();
}

// Favor High: Normal: Low. Caller must hold 'mtx_'.
JobRecord* JobManager::popReadyLocked()
{
    static constexpr int ORDER[] =
    {
        static_cast<int>(JobPriority::High),
        static_cast<int>(JobPriority::Normal),
        static_cast<int>(JobPriority::Low)};

    for (const int idx : ORDER)
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
        // A currently running worker will finish and either requeue or also exit.
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
                // Notify global/per-client idle waiters when the last active worker finishes
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

            switch (res)
            {
                case JobResult::Done:
                {
                    rec->state = JobRecord::State::Done;

                    notifyDependents(rec);

                    // RUNNING leaves the counted set.
                    bumpClientCountLocked(rec->client, -1);

                    // Detach and recycle
                    rec->job->rec_   = nullptr;
                    rec->job->owner_ = nullptr;
                    liveRecs_.erase(rec);
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
                        pushReady(rec, rec->priority);
                        cv_.notify_one();
                    }
                    else
                    {
                        // Park: RUNNING -> WAITING leaves the counted set.
                        rec->state = JobRecord::State::Waiting;
                        bumpClientCountLocked(rec->client, -1);
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
                        bumpClientCountLocked(rec->client, -1);
                    }
                    else
                    {
                        // Dependency already done/unknown: keep runnable (still counted)
                        rec->state = JobRecord::State::Ready;
                        pushReady(rec, rec->priority);
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
                            r->priority  = rec->job->childPriority_;
                            r->client    = rec->client; // inherit parent's client
                            r->state     = JobRecord::State::Ready;
                            r->dependents.clear();
                            r->wakeGen.store(0, std::memory_order_relaxed);

                            rec->job->child_->owner_ = this;
                            rec->job->child_->rec_   = r;

                            childRec = r;

                            // If the client is being canceled, drop the child immediately.
                            if (cancellingClients_.contains(r->client))
                            {
                                // No counting bump (never enters READY set); cancel directly.
                                // Cancel dependents of child (same client cascade handled in cancel).
                                // Here we mimic a Done without ever exposing the record.
                                r->state = JobRecord::State::Done;
                                notifyDependents(r);
                                r->job->rec_   = nullptr;
                                r->job->owner_ = nullptr;
                                freeRecord(r);
                                childRec = nullptr;
                            }
                            else
                            {
                                liveRecs_.insert(r);
                                bumpClientCountLocked(r->client, +1);
                            }
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
                        pushReady(childRec, childRec->priority);
                        cv_.notify_one();
                    }

                    if (!parked)
                    {
                        // Parent stays runnable (still counted).
                        rec->state = JobRecord::State::Ready;
                        pushReady(rec, rec->priority);
                        cv_.notify_one();
                    }
                    else
                    {
                        // Parent parked: RUNNING -> WAITING leaves counted set.
                        rec->state = JobRecord::State::Waiting;
                        bumpClientCountLocked(rec->client, -1);
                    }

                    rec->job->clearIntents();
                    break;
                }
            }
        }
    }
}

//==============================
// Client / Cancel helpers
//==============================

void JobManager::bumpClientCountLocked(ClientId client, int delta)
{
    auto& c = clientReadyRunning_[client];
    c       = static_cast<std::size_t>(static_cast<long long>(c) + delta);
    if (c == 0)
    {
        // Someone may be waiting for this client.
        idleCv_.notify_all();
    }
}

bool JobManager::cancelCascadeLocked(JobRecord* rec, ClientId client)
{
    if (!rec)
        return false;
    if (rec->client != client)
        return false;
    if (rec->state == JobRecord::State::Done)
        return false;
    if (rec->state == JobRecord::State::Running)
        return false;

    // Recursively cancel same-client dependents (they are WAITING on this).
    // Copy out list to avoid iterator invalidation.
    const std::vector<Job*> deps = std::move(rec->dependents);
    rec->dependents.clear();
    for (Job* j : deps)
    {
        if (!j)
            continue;
        if (j->owner_ != this || !j->rec_)
            continue;
        JobRecord* w = j->rec_;
        if (w->client == client)
            cancelCascadeLocked(w, client);
        else
        {
            // Different client: keep dependent for notify in a moment
            rec->dependents.push_back(j);
        }
    }

    // Remove from ready queues if present and adjust counts.
    if (rec->state == JobRecord::State::Ready)
    {
        removeFromReadyQueuesLocked(rec);       // adjusts readyCount_
        bumpClientCountLocked(rec->client, -1); // READY leaves counted set
    }
    else
    {
        // WAITING is not counted; nothing to do for clientReadyRunning_.
        SWAG_ASSERT(rec->state == JobRecord::State::Waiting);
    }

    // Mark done, wake dependents (of other clients), detach, and free.
    rec->state = JobRecord::State::Done;
    notifyDependents(rec);

    if (rec->job)
    {
        rec->job->rec_   = nullptr;
        rec->job->owner_ = nullptr;
    }
    liveRecs_.erase(rec);
    freeRecord(rec);
    return true;
}

JobManager::ClientId JobManager::newClientId()
{
    return nextClientId_.fetch_add(1, std::memory_order_relaxed);
}

SWC_END_NAMESPACE()
