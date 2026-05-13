#include "pch.h"
#include "Support/Thread/JobManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Main/Command/CommandLine.h"
#include "Main/Stats.h"
#include "Support/Os/Os.h"
#include "Support/Report/HardwareException.h"

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

#if SWC_DEV_MODE
namespace
{
    Utf8 debugWaitDependency(const TaskContext& ctx, const TaskState& state)
    {
        if (state.symbol)
            return state.symbol->name(ctx);
        if (state.runJitFunction)
            return Utf8{state.runJitFunction->name(ctx)};

        if (ctx.hasCompiler() && state.idRef.isValid())
            return Utf8{ctx.idMgr().get(state.idRef).name};

        return {};
    }
}
#endif

JobRecord* JobManager::allocRecord()
{
    // Fast path: thread-local
    std::vector<JobRecord*>& v = RecordPool::tls;
    if (!v.empty())
    {
        JobRecord* r = v.back();
        v.pop_back();
        return r;
    }

    // Slow path: global pool
    const std::scoped_lock lk(RecordPool::mtx);
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
    std::vector<JobRecord*>& v = RecordPool::tls;
    if (v.size() < RecordPool::K_TLS_MAX)
    {
        v.push_back(r);
        return;
    }

    const std::scoped_lock lk(RecordPool::mtx);
    RecordPool::freeList.push_back(r);
}

JobManager::~JobManager()
{
    shutdown();
}

void JobManager::setup(const CommandLine& cmdLine)
{
    uint32_t count = cmdLine.numCores;
    cmdLine_       = &cmdLine;

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

    // Reserve a dedicated index for the setup/main thread when workers exist.
    // Worker threads keep [0..numThreads-1], main thread gets numThreads.
    threadIndex_ = singleThreaded_ ? 0 : numThreads;

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
    const std::unique_lock lk(mtx_);
    SWC_ASSERT(accepting_);

    // If already scheduled on this manager, refuse (simplifies invariants).
    SWC_ASSERT(!(job.owner() == this && job.rec() != nullptr));

    // Acquire a Record from the pool and wire it up.
    JobRecord* rec = allocRecord();
    rec->job       = &job;
    rec->priority  = priority;
    rec->clientId  = client;
    rec->state     = JobRecord::State::Ready;
    rec->index     = nextIndex_.fetch_add(1);

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

    const std::unique_lock lk(mtx_);
    if (liveRecs_.empty())
        return;

    std::vector<const JobRecord*> temp;
    temp.reserve(liveRecs_.size());
    for (const JobRecord* rec : liveRecs_)
    {
        if (rec && rec->clientId == client && rec->state == JobRecord::State::Waiting)
            temp.push_back(rec);
    }

    std::ranges::sort(temp, [](const JobRecord* lhs, const JobRecord* rhs) { return lhs->index < rhs->index; });

    for (const JobRecord* t : temp)
        waiting.push_back(t->job);
}

JobRecord* JobManager::popReadyLocked()
{
    for (int idx = static_cast<int>(JobPriority::High); idx <= static_cast<int>(JobPriority::Low); idx++)
    {
        std::deque<JobRecord*>& q = readyQ_[idx];
        if (!q.empty())
        {
#if SWC_DEV_MODE
            uint32_t pickIndex = 0;
            if (singleThreaded_ && cmdLine_->randomize)
                pickIndex = static_cast<uint32_t>(std::rand()) % q.size(); // NOLINT(concurrency-mt-unsafe)
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
        std::deque<JobRecord*>& q = readyQ_[idx];
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
                const uint32_t pickIndex = matches[std::rand() % matches.size()]; // NOLINT(concurrency-mt-unsafe)
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
        idleCv_.wait(lk, [this] { return readyCount_.load(std::memory_order_acquire) == 0 && activeWorkers_.load(std::memory_order_acquire) == 0; });
        return;
    }

    // Single-threaded: run all ready jobs on the calling thread in priority order.
    while (true)
    {
        JobRecord* rec = nullptr;

        {
            const std::unique_lock lk(mtx_);
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
    const std::unique_lock lk(mtx_);

    if (liveRecs_.empty())
        return false;

    std::size_t woken = 0;

    // Sort by job index to be deterministic
    if (singleThreaded_)
    {
        std::vector<JobRecord*> temp;
        temp.reserve(liveRecs_.size());
        for (JobRecord* rec : liveRecs_)
        {
            if (rec && rec->clientId == client && rec->state == JobRecord::State::Waiting)
                temp.push_back(rec);
        }

        std::ranges::sort(temp, [](const JobRecord* lhs, const JobRecord* rhs) { return lhs->index < rhs->index; });
        for (JobRecord* rec : temp)
        {
            rec->state = JobRecord::State::Ready;
            bumpClientCountLocked(rec->clientId, +1);
            pushReady(rec, rec->priority);
            ++woken;
        }
    }
    else
    {
        for (JobRecord* rec : liveRecs_)
        {
            if (!rec)
                continue;
            if (rec->clientId != client)
                continue;
            if (rec->state != JobRecord::State::Waiting)
                continue;
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
        idleCv_.wait(lk, [&] { const auto it = clientReadyRunning_.find(client); return it == clientReadyRunning_.end() || it->second == 0; });
        return;
    }

    // Single-threaded: execute this client's jobs until its ready+running count is 0,
    // or all of its jobs are sleeping.
    while (true)
    {
        JobRecord* rec = nullptr;

        {
            const std::unique_lock lk(mtx_);

            const auto it = clientReadyRunning_.find(client);
            if (it == clientReadyRunning_.end() || it->second == 0)
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

#if SWC_DEV_MODE
Utf8 JobManager::debugDescribeState(std::optional<JobClientId> client) const
{
    const std::unique_lock lk(mtx_);
    return debugDescribeStateLocked(client);
}

bool JobManager::debugHasWaitingJobs(JobClientId client) const
{
    const std::unique_lock lk(mtx_);
    return debugHasWaitingJobsLocked(client);
}

void JobManager::assertNoWaitingJobs(JobClientId client, const std::string_view where) const
{
    Utf8 detail;
    {
        const std::unique_lock lk(mtx_);
        if (!debugHasWaitingJobsLocked(client))
            return;

        detail = debugDescribeStateLocked(client);
    }

    const Utf8 whereText(where);
    swcPanic("Unexpected sleeping jobs detected!", __FILE__, __LINE__, whereText.c_str(), detail.view());
}

Utf8 JobManager::debugDescribeStateLocked(const std::optional<JobClientId> client) const
{
    size_t                  readyCount   = 0;
    size_t                  runningCount = 0;
    size_t                  waitingCount = 0;
    size_t                  doneCount    = 0;
    size_t                  liveCount    = 0;
    std::vector<JobRecord*> waitingJobs;
    waitingJobs.reserve(liveRecs_.size());

    for (JobRecord* rec : liveRecs_)
    {
        if (!rec)
            continue;
        if (client.has_value() && rec->clientId != *client)
            continue;

        liveCount++;
        switch (rec->state)
        {
            case JobRecord::State::Ready:
                readyCount++;
                break;
            case JobRecord::State::Running:
                runningCount++;
                break;
            case JobRecord::State::Waiting:
                waitingCount++;
                waitingJobs.push_back(rec);
                break;
            case JobRecord::State::Done:
                doneCount++;
                break;
        }
    }

    Utf8 detail;
    if (client.has_value())
        detail += std::format("client={}\n", *client);

    detail += std::format("live={} ready={} running={} waiting={} done={} readyCounter={} activeWorkers={}",
                          liveCount,
                          readyCount,
                          runningCount,
                          waitingCount,
                          doneCount,
                          readyCount_.load(std::memory_order_acquire),
                          activeWorkers_.load(std::memory_order_acquire));

    if (client.has_value())
    {
        const auto it = clientReadyRunning_.find(*client);
        detail += std::format(" clientReadyRunning={}", it == clientReadyRunning_.end() ? 0 : it->second);
    }

    detail += "\n";

    if (waitingJobs.empty())
        return detail;

    std::ranges::sort(waitingJobs, [](const JobRecord* lhs, const JobRecord* rhs) { return lhs->index < rhs->index; });
    detail += "waiting jobs:\n";
    for (const JobRecord* rec : waitingJobs)
    {
        SWC_ASSERT(rec != nullptr);
        SWC_ASSERT(rec->job != nullptr);

        const TaskContext& ctx        = rec->job->ctx();
        const TaskState&   taskState  = ctx.state();
        const Utf8         dependency = debugWaitDependency(ctx, taskState);

        detail += std::format("  #{} kind={} wait={}", rec->index, Job::kindName(rec->job->kind()), TaskState::kindName(taskState.kind));
        if (!dependency.empty())
            detail += std::format(" dependency={}", dependency);
        if (taskState.waiterSymbol)
            detail += std::format(" waiter={}", taskState.waiterSymbol->name(ctx));
        detail += "\n";
    }

    return detail;
}

bool JobManager::debugHasWaitingJobsLocked(const JobClientId client) const
{
    for (const JobRecord* rec : liveRecs_)
    {
        if (!rec)
            continue;
        if (rec->clientId != client)
            continue;
        if (rec->state == JobRecord::State::Waiting)
            return true;
    }

    return false;
}
#endif

void JobManager::shutdown() noexcept
{
    {
        const std::unique_lock lk(mtx_);
        if (joined_)
            return;
        accepting_ = false;
        cv_.notify_all();
    }

    for (std::thread& t : workers_)
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
    int exceptionHandler(const Job& job, SWC_LP_EXCEPTION_POINTERS args)
    {
        HardwareException::log(job.ctx(), "hardware exception during job execution", args);
        Stats::addError();
        Os::panicBox("hardware exception raised!");
        return SWC_EXCEPTION_EXECUTE_HANDLER;
    }
}

JobResult JobManager::executeJob(Job& job)
{
    JobResult          res;
    const TaskContext* savedContext = TaskContext::setCurrent(&job.ctx());

    SWC_TRY
    {
        res = job.exec();
    }
    SWC_EXCEPT(exceptionHandler(job, SWC_GET_EXCEPTION_INFOS()))
    {
        res = JobResult::Done;
    }

    TaskContext::setCurrent(savedContext);
    return res;
}

void JobManager::handleJobResult(JobRecord* rec, const JobResult res)
{
    const std::unique_lock lk(mtx_);

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
JobRecord* JobManager::popReadyAndMarkRunningLocked()
{
    JobRecord* rec = popReadyLocked();
    if (!rec)
        return nullptr;
    if (rec->state == JobRecord::State::Done)
        return nullptr;
    rec->state = JobRecord::State::Running;
    activeWorkers_.fetch_add(1, std::memory_order_acq_rel);
    return rec;
}

bool JobManager::isDrainedLocked() const
{
    // Once we stop accepting, threads should exit as soon as the READY queues are empty.
    // A currently running worker will finish and either requeue or also exit.
    return !accepting_ && readyCount_.load(std::memory_order_acquire) == 0;
}

void JobManager::workerLoop()
{
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
                cv_.wait(lk, [this] { return readyCount_.load(std::memory_order_acquire) > 0 || !accepting_; });

                if (isDrainedLocked())
                    return;
                rec = popReadyAndMarkRunningLocked();
            }

            break;
        }

        // If the spin loop did not acquire a job yet, but we observed ready work, do a short locked pop.
        if (!rec)
        {
            const std::unique_lock lk(mtx_);
            if (isDrainedLocked())
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

        const ActiveGuard activeGuard{.ref = &activeWorkers_, .ready = &readyCount_, .idleCv = &idleCv_};

        const JobResult res = executeJob(*rec->job);
        handleJobResult(rec, res);
    }
}

void JobManager::bumpClientCountLocked(JobClientId client, int delta)
{
    std::size_t& c = clientReadyRunning_[client];
    c              = static_cast<std::size_t>(static_cast<long long>(c) + delta);
    if (c == 0)
        idleCv_.notify_all();
}

SWC_END_NAMESPACE();
