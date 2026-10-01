#include "pch.h"
#include "Support/Thread/JobManager.h"
#include "Backend/JIT/JITExecManager.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/HardwareException.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void notifyReadyWorkers(std::condition_variable& cv, size_t readyJobs, size_t workerCount)
    {
        if (!readyJobs || !workerCount)
            return;

        // Small dependency fan-outs should not wake the entire pool just to compete
        // for a handful of jobs. A large wave can use one broadcast.
        if (readyJobs >= workerCount)
            cv.notify_all();
        else
            for (size_t i = 0; i < readyJobs; ++i)
                cv.notify_one();
    }
}

struct JobManager::RecordPool
{
    // Thread-local free list (LIFO for cache locality).
    static thread_local std::vector<std::unique_ptr<JobRecord>> tls;
    static constexpr std::size_t                                K_TLS_MAX = 1024; // cap per thread to avoid unbounded growth
};

thread_local size_t                                  JobManager::threadIndex_   = 0;
thread_local const JobManager*                       JobManager::threadManager_ = nullptr;
thread_local std::vector<std::unique_ptr<JobRecord>> JobManager::RecordPool::tls;

JobRecord* JobManager::allocRecord()
{
    // Job records are short-lived and recycled on the thread that releases them. Keeping
    // the common path thread-local avoids taking the scheduler mutex just to allocate.
    auto& tls = RecordPool::tls;
    if (!tls.empty())
    {
        JobRecord* r = tls.back().release();
        tls.pop_back();
        return r;
    }

    return new JobRecord();
}

void JobManager::freeRecord(JobRecord* r)
{
    SWC_ASSERT(!r->registered && !r->clientWaitPrevious && !r->clientWaitNext && !r->keyWaitPrevious && !r->keyWaitNext);
    // Minimal reset (fields set on reuse anyway).
    r->job      = nullptr;
    r->state    = JobRecord::State::Ready;
    r->priority = JobPriority::Normal;
    r->clientId = 0;

    // Overflow is dropped back to the heap on purpose: a shared spill pool created
    // cross-thread contention in the scheduler, which cost more than a rare reallocation.
    auto& tls = RecordPool::tls;
    if (tls.size() < RecordPool::K_TLS_MAX)
    {
        tls.emplace_back(r);
        return;
    }

    delete r;
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

    configuredWorkerCount_ = singleThreaded_ ? 0 : count;

    // Reserve a dedicated index for the setup/main thread when workers exist.
    // Worker threads keep [0..configuredWorkerCount_-1], main thread gets the last slot.
    threadIndex_   = singleThreaded_ ? 0 : configuredWorkerCount_;
    threadManager_ = this;
    setupThreadId_ = std::this_thread::get_id();

    accepting_ = true;
    joined_    = false;
}

std::optional<size_t> JobManager::currentThreadIndex() const noexcept
{
    if (threadManager_ == this)
        return threadIndex_;
    // A nested/local pool can change TLS on the setup thread. Its slot in this
    // pool is still distinct from every worker's slot.
    if (std::this_thread::get_id() == setupThreadId_)
        return singleThreaded_ ? 0 : configuredWorkerCount_;
    return std::nullopt;
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
    rec->index     = nextIndex_++;

    job.setOwner(this);
    job.setRec(rec);

    bumpClientCountLocked(clients_[client], +1);
    pushReady(rec, priority);
    growWorkersForLoadLocked();
    cv_.notify_one();
}

std::optional<WaitKey> JobManager::computeWaitKey(const TaskState& st)
{
    switch (st.kind)
    {
        // Symbol-flag waits: the producer is Symbol::set*, which wakes {symbol, kind}.
        case TaskStateKind::SemaWaitSymDeclared:
        case TaskStateKind::SemaWaitSymTyped:
        case TaskStateKind::SemaWaitSymConstraintsResolved:
        case TaskStateKind::SemaWaitSymSemaCompleted:
        case TaskStateKind::SemaWaitSymCodeGenPreSolved:
        case TaskStateKind::SemaWaitSymCodeGenCompleted:
        case TaskStateKind::SemaWaitSymJitPrepared:
        case TaskStateKind::SemaWaitSymJitPatched:
        case TaskStateKind::SemaWaitSymJitCompleted:
            if (st.symbol)
                return WaitKey{st.symbol, st.kind};
            return std::nullopt;

        case TaskStateKind::SemaWaitTypeInfoGeneration:
            SWC_ASSERT(st.typeInfoOwner != nullptr);
            return WaitKey{st.typeInfoOwner, st.kind};

        // JIT completion has a separate owner alias, independent of the dependency
        // that currently occupies this record's intrusive key links.
        case TaskStateKind::SemaWaitMainThreadRunJit:
            return std::nullopt;

        // Everything else stays a wildcard sleeper for now (woken by the barrier wakeAll).
        default:
            return std::nullopt;
    }
}

void JobManager::parkLocked(ClientState& client, JobRecord* rec, const TaskState& state)
{
    SWC_ASSERT(rec->state == JobRecord::State::Running);
    rec->state = JobRecord::State::Waiting;
    bumpClientCountLocked(client, -1);

    JobRecord*& clientHead  = client.waitingHead;
    rec->clientWaitPrevious = nullptr;
    rec->clientWaitNext     = clientHead;
    if (clientHead)
        clientHead->clientWaitPrevious = rec;
    clientHead = rec;

    // Keep completion addressable even while the owner waits on an internal JIT
    // dependency. An opaque context key never dereferences a job that has since ended.
    const TaskContext& ownerCtx = rec->job->ctx();
    if (ownerCtx.state().kind == TaskStateKind::SemaWaitMainThreadRunJit)
    {
        const WaitKey ownerKey{&ownerCtx, TaskStateKind::SemaWaitMainThreadRunJit};
        const auto [_, inserted] = waiters_.emplace(ownerKey, rec);
        SWC_ASSERT(inserted);
        filterAdd(ownerKey);
    }

    // Unkeyed waits still belong to the client's list for barrier and cycle handling.
    if (const std::optional<WaitKey> key = computeWaitKey(state))
    {
        rec->waitKey         = *key;
        rec->registered      = true;
        JobRecord*& keyHead  = waiters_[*key];
        rec->keyWaitPrevious = nullptr;
        rec->keyWaitNext     = keyHead;
        if (keyHead)
            keyHead->keyWaitPrevious = rec;
        else
            filterAdd(*key);
        keyHead = rec;
    }
}

void JobManager::unregisterWaiterLocked(ClientState& client, JobRecord* rec)
{
    SWC_ASSERT(rec->state == JobRecord::State::Waiting);
    JobRecord*& clientHead = client.waitingHead;
    if (rec->clientWaitPrevious)
        rec->clientWaitPrevious->clientWaitNext = rec->clientWaitNext;
    else
    {
        SWC_ASSERT(clientHead == rec);
        clientHead = rec->clientWaitNext;
    }
    if (rec->clientWaitNext)
        rec->clientWaitNext->clientWaitPrevious = rec->clientWaitPrevious;
    rec->clientWaitPrevious = nullptr;
    rec->clientWaitNext     = nullptr;

    const TaskContext& ownerCtx = rec->job->ctx();
    if (ownerCtx.state().kind == TaskStateKind::SemaWaitMainThreadRunJit)
    {
        const WaitKey ownerKey{&ownerCtx, TaskStateKind::SemaWaitMainThreadRunJit};
        const auto    it = waiters_.find(ownerKey);
        SWC_ASSERT(it != waiters_.end() && it->second == rec);
        waiters_.erase(it);
        filterSub(ownerKey);
    }

    if (rec->registered)
    {
        const auto it = waiters_.find(rec->waitKey);
        SWC_ASSERT(it != waiters_.end());
        if (rec->keyWaitPrevious)
            rec->keyWaitPrevious->keyWaitNext = rec->keyWaitNext;
        else
        {
            SWC_ASSERT(it->second == rec);
            it->second = rec->keyWaitNext;
        }
        if (rec->keyWaitNext)
            rec->keyWaitNext->keyWaitPrevious = rec->keyWaitPrevious;
        if (!it->second)
        {
            waiters_.erase(it);
            filterSub(rec->waitKey);
        }
        rec->keyWaitPrevious = nullptr;
        rec->keyWaitNext     = nullptr;
        rec->waitKey         = {};
        rec->registered      = false;
    }
}

void JobManager::requeueWaitingLocked(ClientState& client, JobRecord* rec)
{
    unregisterWaiterLocked(client, rec);
    rec->state = JobRecord::State::Ready;
    bumpClientCountLocked(client, +1);
    pushReady(rec, rec->priority);
}

void JobManager::wake(const WaitKey& key)
{
    if (!key.valid())
        return;

    // Lock-free fast path: an empty shard means no job is parked on this key, so there is
    // nothing to wake and no reason to touch the global scheduler mutex. This is what keeps the
    // very frequent symbol-state wakes from serializing every worker on mtx_ when, as is almost
    // always the case, nobody waits on that exact dependency.
    if (waiterFilter_[waiterShard(key)].load(std::memory_order_acquire) == 0)
        return;

    const std::unique_lock lk(mtx_);

    const auto it = waiters_.find(key);
    if (it == waiters_.end())
        return;

    if (key.kind == TaskStateKind::SemaWaitMainThreadRunJit)
    {
        // This is the owner's unique alias, not its dependency's intrusive list.
        requeueWaitingLocked(clients_[it->second->clientId], it->second);
        growWorkersForLoadLocked();
        cv_.notify_one();
        return;
    }

    size_t woken = 0;
    for (JobRecord* rec = it->second; rec;)
    {
        JobRecord* next = rec->keyWaitNext;
        requeueWaitingLocked(clients_[rec->clientId], rec);
        rec = next;
        ++woken;
    }

    growWorkersForLoadLocked();

    notifyReadyWorkers(cv_, woken, workers_.size());
}

void JobManager::refreshJitWait(const TaskContext* owner)
{
    const WaitKey ownerKey{owner, TaskStateKind::SemaWaitMainThreadRunJit};
    if (waiterFilter_[waiterShard(ownerKey)].load(std::memory_order_acquire) == 0)
        return;

    const std::unique_lock lock(mtx_);
    const auto it = waiters_.find(ownerKey);
    if (it == waiters_.end())
        return;

    // The lane paused after its owner parked. Replace the registration in place;
    // the owner neither executes nor joins the ready queue unless already satisfied.
    JobRecord*   rec    = it->second;
    ClientState& client = clients_[rec->clientId];
    unregisterWaiterLocked(client, rec);
    rec->state = JobRecord::State::Running;
    bumpClientCountLocked(client, +1);
    handleJobResultLocked(rec, JobResult::Sleep);
}

void JobManager::waitingJobs(std::vector<Job*>& waiting, JobClientId client) const
{
    waiting.clear();

    const std::unique_lock lk(mtx_);
    const auto             it = clients_.find(client);
    if (it == clients_.end())
        return;

    std::vector<const JobRecord*> temp;
    for (const JobRecord* rec = it->second.waitingHead; rec; rec = rec->clientWaitNext)
        temp.push_back(rec);

    std::ranges::sort(temp, {}, &JobRecord::index);

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
            --readyCount_;
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
                --readyCount_;
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
            --readyCount_;
            return rec;
        }
    }

    return nullptr;
}

void JobManager::waitAll()
{
    if (!singleThreaded_)
    {
        // In worker mode, wait for the global ready queue to drain and for every worker
        // that already claimed a job to publish its result.
        std::unique_lock lk(mtx_);
        idleCv_.wait(lk, [this] { return readyCount_ == 0 && activeWorkers_ == 0; });
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
            // The client's ready/running count already includes this job from enqueue().
            // We do NOT touch bumpClientCountLocked() here, just like in workerLoop().
        }

        const JobResult        res = executeJob(*rec->job);
        const std::unique_lock lk(mtx_);
        handleJobResultLocked(rec, res);
    }
}

bool JobManager::wakeAll(JobClientId client)
{
    const std::unique_lock lk(mtx_);

    const auto clientIt = clients_.find(client);
    if (clientIt == clients_.end() || !clientIt->second.waitingHead)
        return false;

    std::size_t woken = 0;

    // Sort by job index to be deterministic
    if (singleThreaded_)
    {
        std::vector<JobRecord*> temp;
        for (JobRecord* rec = clientIt->second.waitingHead; rec; rec = rec->clientWaitNext)
            temp.push_back(rec);

        std::ranges::sort(temp, {}, &JobRecord::index);
        for (JobRecord* rec : temp)
        {
            requeueWaitingLocked(clientIt->second, rec);
            ++woken;
        }
    }
    else
    {
        while (JobRecord* rec = clientIt->second.waitingHead)
        {
            requeueWaitingLocked(clientIt->second, rec);
            ++woken;
        }
    }

    if (woken != 0)
    {
        growWorkersForLoadLocked();
        notifyReadyWorkers(cv_, woken, workers_.size());
    }

    return woken != 0;
}

void JobManager::waitAll(JobClientId client)
{
    if (!singleThreaded_)
    {
        // Per-client waiting watches ready+running jobs only. Sleeping jobs are excluded
        // so the caller can perform the compiler action that may wake them.
        std::unique_lock lk(mtx_);
        idleCv_.wait(lk, [&] { const auto it = clients_.find(client); return it == clients_.end() || it->second.readyRunning == 0; });
        return;
    }

    // Single-threaded: execute this client's jobs until its ready+running count is 0,
    // or all of its jobs are sleeping.
    while (true)
    {
        JobRecord* rec = nullptr;

        {
            const std::unique_lock lk(mtx_);

            const auto it = clients_.find(client);
            if (it == clients_.end() || it->second.readyRunning == 0)
                break;

            rec = popReadyForClientLocked(client);

            // No ready jobs for this client (only sleepers): nothing more to do now.
            if (!rec)
                break;

            if (rec->state == JobRecord::State::Done)
                continue;

            rec->state = JobRecord::State::Running;
        }

        const JobResult        res = executeJob(*rec->job);
        const std::unique_lock lk(mtx_);
        handleJobResultLocked(rec, res);
    }
}

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
    if (threadManager_ == this)
        threadManager_ = nullptr;

    // NOTE: User code still owns remaining sleepers (if any).
    // They are not runnable; their rec_ remains set until they are woken and run to completion.
}

void JobManager::pushReady(JobRecord* rec, JobPriority priority)
{
    readyQ_[static_cast<int>(priority)].push_back(rec);
    ++readyCount_;
}

void JobManager::growWorkersForLoadLocked()
{
    if (singleThreaded_ || !accepting_)
        return;

    const size_t desiredWorkers = std::min<size_t>(configuredWorkerCount_, readyCount_ + activeWorkers_);

    if (workers_.size() >= desiredWorkers)
        return;

    workers_.reserve(configuredWorkerCount_);
    while (workers_.size() < desiredWorkers)
    {
        const size_t threadIndex = workers_.size();
        workers_.emplace_back([this, threadIndex] {
            threadIndex_   = threadIndex;
            threadManager_ = this;
            Os::reserveFaultHandlerStack();
            workerLoop();
        });
    }
}

namespace
{
    void reportSilentJobFailure(Job& job, JobResult result)
    {
        // Expected source errors are recorded even when the test harness suppresses them.
        TaskContext& ctx = job.ctx();
        if (result != JobResult::Error || ctx.hasError() || ctx.silentDiagnostic() || Stats::hasError() || (ctx.hasCompiler() && ctx.compiler().hasErrorDiagnostic()))
            return;

        auto diagnostic = Diagnostic::get(DiagnosticId::cmd_err_job_failed_silently);
        diagnostic.addArgument(Diagnostic::ARG_WHAT, Job::kindName(job.kind()));
        diagnostic.report(ctx);
    }

    int exceptionHandler(const Job& job, SWC_LP_EXCEPTION_POINTERS args)
    {
        uint32_t    exceptionCode    = 0;
        const void* exceptionAddress = nullptr;
        Os::decodeHostException(exceptionCode, exceptionAddress, args);
        SWC_UNUSED(exceptionAddress);
        if (!Os::isFatalHostException(exceptionCode))
            return SWC_EXCEPTION_CONTINUE_SEARCH;

        HardwareException::log(job.ctx(), "hardware exception during job execution", args);
        Stats::addError();
        Os::panicBox("hardware exception during job execution");
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
        reportSilentJobFailure(job, res);
    }
    SWC_EXCEPT(exceptionHandler(job, SWC_GET_EXCEPTION_INFOS()))
    {
        res = JobResult::Done;
    }

    TaskContext::setCurrent(savedContext);
    return res;
}

void JobManager::handleJobResultLocked(JobRecord* rec, const JobResult res)
{
    ClientState& client = clients_[rec->clientId];
    switch (res)
    {
        case JobResult::Done:
        case JobResult::Error:
        {
            rec->state = JobRecord::State::Done;
            bumpClientCountLocked(client, -1);

            // Detach and recycle the record
            rec->job->setRec(nullptr);
            rec->job->setOwner(nullptr);
            freeRecord(rec);
            break;
        }

        case JobResult::Sleep:
        {
            TaskContext&                            ctx   = rec->job->ctx();
            const TaskState*                        state = &ctx.state();
            std::optional<JITExecManager::OwnerWait> jitWait;
            if (state->kind == TaskStateKind::SemaWaitMainThreadRunJit)
            {
                jitWait.emplace(ctx.compiler().jitExecMgr().acquireOwnerWait(ctx));
                state = jitWait->state;
            }

            parkLocked(client, rec, *state);
            // The no-op RMW either observes the owner's release or publishes this
            // registration to that release before the producer checks the waiter filter.
            const bool typeInfoReleased = state->kind == TaskStateKind::SemaWaitTypeInfoGeneration &&
                                          state->typeInfoOwner->fetch_or(0, std::memory_order_acq_rel) != state->typeInfoGeneration;
            if ((state->symbol && state->symbol->isWaitSatisfied(state->kind)) || typeInfoReleased || (jitWait && jitWait->completed))
            {
                // Publication can precede registration. Symbol flag RMWs and the JIT
                // completion mutex close that window without a global barrier retry.
                requeueWaitingLocked(client, rec);
                cv_.notify_one();
            }
            break;
        }
    }
}

bool JobManager::isDrainedLocked() const
{
    // Once we stop accepting, threads should exit as soon as the READY queues are empty.
    // A currently running worker will finish and either requeue or also exit.
    return !accepting_ && readyCount_ == 0;
}

void JobManager::workerLoop()
{
    std::unique_lock lk(mtx_);
    while (true)
    {
        // An idle worker leaves the CPU to jobs that can make progress. Completion
        // and the next dequeue share one lock acquisition while work remains ready.
        cv_.wait(lk, [this] { return readyCount_ != 0 || !accepting_; });
        if (isDrainedLocked())
            return;

        JobRecord* rec = popReadyLocked();
        SWC_ASSERT(rec && rec->state == JobRecord::State::Ready);
        rec->state = JobRecord::State::Running;
        ++activeWorkers_;
        lk.unlock();
        const JobResult res = executeJob(*rec->job);
        lk.lock();
        handleJobResultLocked(rec, res);
        --activeWorkers_;

        // Publish the idle predicate under the waiter's mutex. Updating the active
        // count outside it can lose the notification between its check and wait.
        if (activeWorkers_ == 0 && readyCount_ == 0)
            idleCv_.notify_all();
    }
}

void JobManager::bumpClientCountLocked(ClientState& client, int delta)
{
    std::size_t& c = client.readyRunning;
    c              = static_cast<std::size_t>(static_cast<long long>(c) + delta);
    if (c == 0)
        idleCv_.notify_all();
}

SWC_END_NAMESPACE();
