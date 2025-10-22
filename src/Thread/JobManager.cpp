#include "pch.h"

#include "Thread/JobManager.h"

// ========================= Record pool (recycling) =========================
//
// We use a simple hybrid pool:
//  • A thread_local vector for super-fast alloc/free on the same thread.
//  • A small global fallback vector under a mutex.
// This avoids per-job heap allocation and keeps Record* stable while in use.
//
// Records are POD-like and reset by the manager before reuse.
//

struct JobManager::RecordPool
{
    // Thread-local free list (LIFO for cache locality).
    static thread_local std::vector<JobRecord*> tls;

    // Global fallback (small), guarded by a mutex.
    static std::mutex            gMutex;
    static std::vector<JobRecord*>  gFree;
    static constexpr std::size_t K_TLS_MAX = 1024; // cap per thread to avoid unbounded growth
};

thread_local std::vector<JobRecord*> JobManager::RecordPool::tls;
std::mutex                        JobManager::RecordPool::gMutex;
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
    std::lock_guard<std::mutex> lk(RecordPool::gMutex);
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
    std::lock_guard<std::mutex> lk(RecordPool::gMutex);
    RecordPool::gFree.push_back(r);
}

// ============================== ctor/dtor ==============================

JobManager::JobManager() = default;

JobManager::~JobManager()
{
    shutdown();
}

// ====================== public: threads & lifecycle ====================

void JobManager::setNumThreads(std::size_t count)
{
    if (count == 0)
        count = std::thread::hardware_concurrency();

    std::unique_lock<std::mutex> lk(mtx_);

    if (!workers_.empty())
    {
        // Stop the current pool cleanly.
        accepting_ = false;
        cv_.notify_all();
        lk.unlock();
        joinAll();
        lk.lock();
        clearThreads();
    }

    // Start a fresh pool.
    accepting_ = true;
    joined_    = false;
    workers_.reserve(count);
    for (std::size_t i = 0; i < count; ++i)
        workers_.emplace_back([this] { workerLoop(); });
}

bool JobManager::enqueue(const JobRef& job, JobPriority prio)
{
    if (!job)
        return false;

    std::unique_lock<std::mutex> lk(mtx_);
    if (!accepting_)
        return false;

    // If already scheduled on this manager, refuse (simplifies invariants).
    if (job->owner_ == this && job->rec_ != nullptr)
        return false;

    // Acquire a Record from the pool and wire it up.
    JobRecord* rec = allocRecord();
    rec->job    = job; // keep job alive while scheduled
    rec->prio   = prio;
    rec->state  = JobRecord::State::Ready;
    rec->dependents.clear();
    rec->wakeGen.store(0, std::memory_order_relaxed);

    job->owner_ = this;
    job->rec_   = rec;

    pushReady(rec, prio);
    cv_.notify_one();
    return true;
}

bool JobManager::wake(const JobRef& job)
{
    if (!job)
        return false;

    std::unique_lock<std::mutex> lk(mtx_);
    // If not scheduled on this manager (or already completed), ignore.
    if (job->owner_ != this || job->rec_ == nullptr)
        return false;

    JobRecord* rec = job->rec_;
    // Arm against lost-wake during a run.
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
    std::unique_lock<std::mutex> lk(mtx_);
    idleCv_.wait(lk, [this] {
        return readyCount_.load(std::memory_order_acquire) == 0 && activeWorkers_ == 0;
    });
}

void JobManager::shutdown() noexcept
{
    {
        std::unique_lock<std::mutex> lk(mtx_);
        if (joined_)
            return;
        accepting_ = false;
        cv_.notify_all();
    }
    joinAll();

    // NOTE: Remaining sleepers (if any) are still owned by user code.
    // They are not runnable; their rec_ remains set until they complete or are canceled.
}

// =============================== internals =============================

void JobManager::pushReady(JobRecord* rec, JobPriority prio)
{
    readyQ_[static_cast<int>(prio)].push_back(rec);
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
// We copy out the vector (move) to minimize lock hold time and avoid re-entrancy pitfalls.
void JobManager::notifyDependents(JobRecord* finished)
{
    const auto deps = std::move(finished->dependents);
    finished->dependents.clear();

    for (const Job* wjob : deps)
    {
        // If the waiter is still scheduled here, it must have a non-null rec_.
        if (wjob && wjob->owner_ == this && wjob->rec_)
        {
            JobRecord* rec = wjob->rec_;
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

// Favor High → Normal → Low. Caller must hold mtx_.
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
    // Small spin to avoid CV storms for micro-jobs under bursts.
    constexpr int spinIters = 200;

    for (;;)
    {
        JobRecord* rec = nullptr;

        // Spin/yield briefly if no ready work, then fall back to CV wait.
        int spins = 0;
        while (readyCount_.load(std::memory_order_acquire) == 0 && accepting_)
        {
            if (++spins < spinIters)
            {
                std::this_thread::yield();
                continue;
            }
            std::unique_lock<std::mutex> lk(mtx_);
            cv_.wait(lk, [this] { return readyCount_.load(std::memory_order_acquire) > 0 || !accepting_; });
            if (!accepting_ && readyCount_.load(std::memory_order_acquire) == 0)
                return;
            rec = popReadyLocked();
            if (rec)
            {
                if (rec->state == JobRecord::State::Done)
                {
                    rec = nullptr;
                    continue;
                }
                rec->state = JobRecord::State::Running;
                ++activeWorkers_;
            }
            goto have_job;
        }

        // We observed ready work; pop with a short lock.
        {
            std::unique_lock<std::mutex> lk(mtx_);
            if (!accepting_ && readyCount_.load(std::memory_order_acquire) == 0)
                return;
            rec = popReadyLocked();
            if (rec)
            {
                if (rec->state == JobRecord::State::Done)
                {
                    rec = nullptr;
                    continue;
                }
                rec->state = JobRecord::State::Running;
                ++activeWorkers_;
            }
        }

    have_job:
        if (!rec)
            continue;

        // Snapshot wake ticket at start.
        const auto wakeAtStart = rec->wakeGen.load(std::memory_order_acquire);

        Job::Result res;
        try
        {
            res = rec->job->process();
        }
        catch (...)
        {
            res = Job::Result::Done;
        } // keep the pool alive

        {
            std::unique_lock<std::mutex> lk(mtx_);

            auto finish = [&](JobRecord* r) {
                r->state = JobRecord::State::Done;
                notifyDependents(r); // auto-wake all dependents
                // cut the link from job → rec, then recycle the record memory
                r->job->rec_   = nullptr;
                r->job->owner_ = nullptr; // job is no longer owned by this manager
                freeRecord(r);
            };

            const bool lostWakePrevented =
            (res == Job::Result::Sleep) &&
            (rec->wakeGen.load(std::memory_order_acquire) != wakeAtStart);

            switch (res)
            {
                case Job::Result::Done:
                {
                    finish(rec);
                    break;
                }
                case Job::Result::Sleep:
                {
                    if (lostWakePrevented)
                    {
                        // Someone called wake() while running → don't park.
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
                case Job::Result::SleepOn:
                {
                    JobRecord* depRec = nullptr;
                    if (rec->job->dep_ && rec->job->dep_->owner_ == this)
                        depRec = rec->job->dep_->rec_;

                    if (depRec && linkOrSkip(rec, depRec))
                    {
                        // parked successfully
                    }
                    else
                    {
                        // dependency already done/unknown → keep runnable
                        rec->state = JobRecord::State::Ready;
                        pushReady(rec, rec->prio);
                        cv_.notify_one();
                    }
                    rec->job->clearIntents();
                    break;
                }
                case Job::Result::SpawnAndSleep:
                {
                    // Create or reuse child's record and enqueue.
                    JobRecord* childRec = nullptr;
                    if (rec->job->child_)
                    {
                        // If the child is already owned/enqueued here, refuse (defensive).
                        if (rec->job->child_->owner_ != this || rec->job->child_->rec_ == nullptr)
                        {
                            JobRecord* r = allocRecord();
                            r->job    = rec->job->child_;
                            r->prio   = rec->job->childPriority_;
                            r->state  = JobRecord::State::Ready;
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

            if (--activeWorkers_ == 0 && readyCount_.load(std::memory_order_acquire) == 0)
                idleCv_.notify_all();
        }
    }
}

void JobManager::joinAll() noexcept
{
    if (joined_)
        return;
    for (auto& t : workers_)
        if (t.joinable())
            t.join();
    joined_ = true;
}

void JobManager::clearThreads()
{
    workers_.clear();
}
