#include "pch.h"
#include "Thread/JobManager.h"
#include "Main/CommandLine.h"
#include "Main/Global.h"
#include "Os/Os.h"
#include "Report/LogColor.h"
#include "Report/Logger.h"

SWC_BEGIN_NAMESPACE();

struct JobManager::RecordPool
{
    // Thread-local free list (LIFO for cache locality).
    static thread_local std::vector<JobRecord*> tls;

    // Global fallback (small), guarded by a mutex.
    static std::mutex              mtx;
    static std::vector<JobRecord*> freeList;
    static constexpr std::size_t   K_TLS_MAX = 1024; // cap per thread to avoid unbounded growth
};

thread_local size_t                  JobManager::threadIndex_ = 0;
thread_local std::vector<JobRecord*> JobManager::RecordPool::tls;
std::mutex                           JobManager::RecordPool::mtx;
std::vector<JobRecord*>              JobManager::RecordPool::freeList;

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
    std::scoped_lock lk(RecordPool::mtx);
    if (!RecordPool::freeList.empty())
    {
        JobRecord* r = RecordPool::freeList.back();
        RecordPool::freeList.pop_back();
        return r;
    }

    // Fallback: heap
    return new JobRecord();
}

void JobManager::freeRecord(JobRecord* r)
{
    // Minimal reset (fields set on reuse anyway).
    r->job      = nullptr;
    r->state    = JobRecord::State::Ready;
    r->priority = JobPriority::Normal;
    r->clientId = 0;

    // Try to return to TLS; spill to global if TLS is full.
    auto& v = RecordPool::tls;
    if (v.size() < RecordPool::K_TLS_MAX)
    {
        v.push_back(r);
        return;
    }

    std::scoped_lock lk(RecordPool::mtx);
    RecordPool::freeList.push_back(r);
}

JobManager::~JobManager()
{
    shutdown();
}

void JobManager::setup(const CommandLine& cmdLine)
{
    auto count = cmdLine.numCores;
    cmdLine_   = &cmdLine;

#if SWC_DEV_MODE
    if (cmdLine_->randomize)
    {
        randSeed_ = cmdLine_->randSeed;
        if (!randSeed_)
        {
            using namespace std::chrono;
            const milliseconds ms = duration_cast<milliseconds>(system_clock::now().time_since_epoch());
            randSeed_             = static_cast<uint32_t>(ms.count());
        }

        srand(randSeed_);
    }
#endif

    if (count == 0)
        count = std::thread::hardware_concurrency();

    // Decide mode: one core => fully synchronous, no worker threads.
    singleThreaded_ = (count <= 1);

    const size_t numThreads = singleThreaded_ ? 0 : count;

    accepting_ = true;
    joined_    = false;

    workers_.reserve(numThreads);
    for (size_t i = 0; i < numThreads; ++i)
        workers_.emplace_back([&, i] {
            threadIndex_ = i;
            workerLoop();
        });
}

JobClientId JobManager::newClientId()
{
    return nextClientId_.fetch_add(1, std::memory_order_relaxed);
}

void JobManager::enqueue(Job& job, JobPriority priority, JobClientId client)
{
    std::unique_lock lk(mtx_);
    SWC_ASSERT(accepting_);

    // If already scheduled on this manager, refuse (simplifies invariants).
    SWC_ASSERT(!(job.owner() == this && job.rec() != nullptr));

    // Acquire a Record from the pool and wire it up.
    JobRecord* rec = allocRecord();
    rec->job       = &job;
    rec->priority  = priority;
    rec->clientId  = client;
    rec->state     = JobRecord::State::Ready;

    job.setOwner(this);
    job.setRec(rec);

    liveRecs_.insert(rec);
    bumpClientCountLocked(client, +1);
    pushReady(rec, priority);
    cv_.notify_one();
}

void JobManager::waitingJobs(std::vector<Job*>& waiting, JobClientId client) const
{
    waiting.clear();

    std::unique_lock lk(mtx_);

    if (liveRecs_.empty())
        return;

    for (const JobRecord* rec : liveRecs_)
    {
        if (!rec)
            continue;
        if (rec->clientId != client)
            continue;

        if (rec->state == JobRecord::State::Waiting)
            waiting.push_back(rec->job);
    }
}

JobRecord* JobManager::popReadyLocked()
{
    for (int idx = static_cast<int>(JobPriority::High); idx <= static_cast<int>(JobPriority::Low); idx++)
    {
        auto& q = readyQ_[idx];
        if (!q.empty())
        {
#if SWC_DEV_MODE
            uint32_t pickIndex = 0;
            if (singleThreaded_ && cmdLine_->randomize)
                pickIndex = static_cast<uint32_t>(rand()) % q.size(); // NOLINT(concurrency-mt-unsafe)
            JobRecord* rec = q[pickIndex];
            q.erase(q.begin() + pickIndex);
#else
            JobRecord* rec = q.front();
            q.pop_front();
#endif
            readyCount_.fetch_sub(1, std::memory_order_acq_rel);
            return rec;
        }
    }

    return nullptr;
}

JobRecord* JobManager::popReadyForClientLocked(JobClientId client)
{
    for (int idx = static_cast<int>(JobPriority::High); idx <= static_cast<int>(JobPriority::Low); idx++)
    {
        auto& q = readyQ_[idx];
        if (q.empty())
            continue;

#if SWC_DEV_MODE
        if (singleThreaded_ && cmdLine_->randomize)
        {
            // Collect indices of matching jobs
            std::vector<uint32_t> matches;
            for (uint32_t i = 0; i < q.size(); ++i)
            {
                const JobRecord* rec = q[i];
                if (rec && rec->clientId == client)
                    matches.push_back(i);
            }

            if (!matches.empty())
            {
                const uint32_t pickIndex = matches[rand() % matches.size()]; // NOLINT(concurrency-mt-unsafe)
                JobRecord*     rec       = q[pickIndex];
                q.erase(q.begin() + pickIndex);
                readyCount_.fetch_sub(1, std::memory_order_acq_rel);
                return rec;
            }

            continue;
        }
#endif

        for (auto it = q.begin(); it != q.end(); ++it)
        {
            JobRecord* rec = *it;
            if (!rec || rec->clientId != client)
                continue;

            q.erase(it);
            readyCount_.fetch_sub(1, std::memory_order_acq_rel);
            return rec;
        }
    }

    return nullptr;
}

void JobManager::waitAll()
{
    if (!singleThreaded_)
    {
        // Existing multithreaded behavior
        std::unique_lock lk(mtx_);
        idleCv_.wait(lk, [this] {
            return readyCount_.load(std::memory_order_acquire) == 0 &&
                   activeWorkers_.load(std::memory_order_acquire) == 0;
        });
        return;
    }

    // Single-threaded: run all ready jobs on the calling thread in priority order.
    while (true)
    {
        JobRecord* rec = nullptr;

        {
            std::unique_lock lk(mtx_);
            rec = popReadyLocked();
            if (!rec)
                break;

            if (rec->state == JobRecord::State::Done)
                continue;

            rec->state = JobRecord::State::Running;
            // Note: clientReadyRunning_ already includes this job from enqueue().
            // We do NOT touch bumpClientCountLocked() here, just like in workerLoop().
        }

        const JobResult res = executeJob(*rec->job);
        handleJobResult(rec, res);
    }
}

bool JobManager::wakeAll(JobClientId client)
{
    std::unique_lock lk(mtx_);

    if (liveRecs_.empty())
        return false;

    std::size_t woken = 0;

    for (JobRecord* rec : liveRecs_)
    {
        if (!rec)
            continue;
        if (rec->clientId != client)
            continue;

        if (rec->state == JobRecord::State::Waiting)
        {
            rec->state = JobRecord::State::Ready;
            bumpClientCountLocked(rec->clientId, +1);
            pushReady(rec, rec->priority);
            ++woken;
        }
    }

    if (woken != 0)
        cv_.notify_all();

    return woken != 0;
}

void JobManager::waitAll(JobClientId client)
{
    if (!singleThreaded_)
    {
        // Existing multithreaded behavior
        std::unique_lock lk(mtx_);
        idleCv_.wait(lk, [&] {
            const auto        it = clientReadyRunning_.find(client);
            const std::size_t n  = (it == clientReadyRunning_.end()) ? 0 : it->second;
            return n == 0;
        });
        return;
    }

    // Single-threaded: execute this client's jobs until its ready+running count is 0,
    // or all of its jobs are sleeping.
    while (true)
    {
        JobRecord* rec = nullptr;

        {
            std::unique_lock lk(mtx_);

            const auto it = clientReadyRunning_.find(client);
            const auto n  = (it == clientReadyRunning_.end()) ? 0 : it->second;
            if (n == 0)
                break;

            rec = popReadyForClientLocked(client);

            // No ready jobs for this client (only sleepers): nothing more to do now.
            if (!rec)
                break;

            if (rec->state == JobRecord::State::Done)
                continue;

            rec->state = JobRecord::State::Running;
        }

        const JobResult res = executeJob(*rec->job);
        handleJobResult(rec, res);
    }
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
    // They are not runnable; their rec_ remains set until they are woken and run to completion.
}

void JobManager::pushReady(JobRecord* rec, JobPriority priority)
{
    readyQ_[static_cast<int>(priority)].push_back(rec);
    readyCount_.fetch_add(1, std::memory_order_release);
}

namespace
{
    void exceptionMessage(const Job& job, SWC_LP_EXCEPTION_POINTERS args)
    {
        const auto& ctx    = job.ctx();
        auto&       logger = ctx.global().logger();

        logger.lock();

        Utf8 msg;
        msg += LogColorHelper::toAnsi(ctx, LogColor::Red);
        msg += "fatal error: hardware exception during job execution!\n";
        msg += std::format("exception code: 0x{}\n", args->ExceptionRecord->ExceptionCode);
        msg += LogColorHelper::toAnsi(ctx, LogColor::Reset);
        Logger::print(ctx, msg);

        logger.unlock();
    }

    int exceptionHandler(const Job& job, SWC_LP_EXCEPTION_POINTERS args)
    {
        const auto& ctx = job.ctx();

        if (Os::isDebuggerAttached() || ctx.cmdLine().dbgDevMode)
        {
            Os::panicBox("Hardware exception raised!");
            return SWC_EXCEPTION_CONTINUE_EXECUTION;
        }

        exceptionMessage(job, args);
        return SWC_EXCEPTION_EXECUTE_HANDLER;
    }
}

JobResult JobManager::executeJob(const Job& job)
{
    JobResult res;

    SWC_TRY
    {
        res = job.func();
    }
    SWC_EXCEPT(exceptionHandler(job, SWC_GET_EXCEPTION_INFOS()))
    {
        res = JobResult::Done;
    }

    return res;
}

void JobManager::handleJobResult(JobRecord* rec, const JobResult res)
{
    std::unique_lock lk(mtx_);

    switch (res)
    {
        case JobResult::Done:
        {
            rec->state = JobRecord::State::Done;
            bumpClientCountLocked(rec->clientId, -1);

            // Detach and recycle the record
            rec->job->setRec(nullptr);
            rec->job->setOwner(nullptr);
            liveRecs_.erase(rec);
            freeRecord(rec);
            break;
        }

        case JobResult::Sleep:
        {
            rec->state = JobRecord::State::Waiting;
            bumpClientCountLocked(rec->clientId, -1);
            break;
        }
    }
}
void JobManager::workerLoop()
{
    auto popReadyAndMarkRunningLocked = [this]() -> JobRecord* {
        JobRecord* rec = popReadyLocked();
        if (!rec)
            return nullptr;
        if (rec->state == JobRecord::State::Done)
            return nullptr;
        rec->state = JobRecord::State::Running;
        activeWorkers_.fetch_add(1, std::memory_order_acq_rel);
        return rec;
    };

    // Once we stop accepting, threads should exit as soon as the READY queues are empty.
    // A currently running worker will finish and either requeue or also exit.
    auto maybeExitIfDrainedLocked = [this]() -> bool {
        return !accepting_ && readyCount_.load(std::memory_order_acquire) == 0;
    };

    while (true)
    {
        JobRecord* rec = nullptr;

        // Fast path: brief spin/yield if no ready work
        int spins = 0;
        while (readyCount_.load(std::memory_order_acquire) == 0 && accepting_)
        {
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
                if (ref->fetch_sub(1, std::memory_order_acq_rel) == 1 &&
                    ready->load(std::memory_order_acquire) == 0)
                    idleCv->notify_all();
            }
        };

        ActiveGuard activeGuard{.ref = &activeWorkers_, .ready = &readyCount_, .idleCv = &idleCv_};

        const JobResult res = executeJob(*rec->job);
        handleJobResult(rec, res);
    }
}

void JobManager::bumpClientCountLocked(JobClientId client, int delta)
{
    auto& c = clientReadyRunning_[client];
    c       = static_cast<std::size_t>(static_cast<long long>(c) + delta);
    if (c == 0)
        idleCv_.notify_all();
}

SWC_END_NAMESPACE();
