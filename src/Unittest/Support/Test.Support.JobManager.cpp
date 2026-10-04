#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Support/Thread/JobManager.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class SleepOnceJob final : public Job
    {
    public:
        explicit SleepOnceJob(const TaskContext& ctx) :
            Job(ctx, JobKind::Parser)
        {
        }

        JobResult exec() override
        {
            if (slept_)
            {
                ctx().state().setNone();
                return JobResult::Done;
            }

            slept_ = true;

            TaskState& wait = ctx().state();
            wait.kind       = TaskStateKind::SemaWaitIdentifier;
            wait.codeRef    = SourceCodeRef::invalid();
            wait.nodeRef    = AstNodeRef::invalid();
            wait.idRef      = IdentifierRef::invalid();
            return JobResult::Sleep;
        }

    private:
        bool slept_ = false;
    };

    // Sleeps once on a precise symbol-typed dependency, so it can be woken by a targeted wake().
    class SleepOnSymTypedJob final : public Job
    {
    public:
        SleepOnSymTypedJob(const TaskContext& ctx, const Symbol* target) :
            Job(ctx, JobKind::Sema),
            target_(target)
        {
        }

        JobResult exec() override
        {
            if (slept_)
            {
                ctx().state().setNone();
                return JobResult::Done;
            }

            slept_ = true;

            TaskState& wait = ctx().state();
            wait.kind       = TaskStateKind::SemaWaitSymTyped;
            wait.symbol     = target_;
            return JobResult::Sleep;
        }

    private:
        const Symbol* target_ = nullptr;
        bool          slept_  = false;
    };

    // Sleeps once on a name, as a lookup that found no symbol for it does.
    class SleepOnNameJob final : public Job
    {
    public:
        SleepOnNameJob(const TaskContext& ctx, IdentifierRef idRef, TaskStateKind kind) :
            Job(ctx, JobKind::Sema),
            idRef_(idRef),
            kind_(kind)
        {
        }

        JobResult exec() override
        {
            if (slept_)
            {
                ctx().state().setNone();
                return JobResult::Done;
            }

            slept_ = true;

            TaskState& wait = ctx().state();
            wait.kind       = kind_;
            wait.idRef      = idRef_;
            return JobResult::Sleep;
        }

    private:
        IdentifierRef idRef_;
        TaskStateKind kind_;
        bool          slept_ = false;
    };

    struct SymbolPublication
    {
        TaskStateKind kind;
        void (Symbol::*publish)(TaskContext&);
    };

    constexpr SymbolPublication SYMBOL_PUBLICATIONS[] = {
        {TaskStateKind::SemaWaitSymDeclared, &Symbol::setDeclared},
        {TaskStateKind::SemaWaitSymTyped, &Symbol::setTyped},
        {TaskStateKind::SemaWaitSymConstraintsResolved, &Symbol::setConstraintsResolved},
        {TaskStateKind::SemaWaitSymSemaCompleted, &Symbol::setSemaCompleted},
        {TaskStateKind::SemaWaitSymCodeGenPreSolved, &Symbol::setCodeGenPreSolved},
        {TaskStateKind::SemaWaitSymCodeGenCompleted, &Symbol::setCodeGenCompleted},
        {TaskStateKind::SemaWaitSymCodeGenPreSolved, &Symbol::setCodeGenCompleted},
    };

    class SymbolPublicationJob final : public Job
    {
    public:
        SymbolPublicationJob(const TaskContext& ctx, Symbol& symbol, SymbolPublication publication, bool publishBeforeParking) :
            Job(ctx, JobKind::Sema),
            symbol_(&symbol),
            publication_(publication),
            publishBeforeParking_(publishBeforeParking)
        {
        }

        JobResult exec() override
        {
            if (slept_)
            {
                completed = payload == 42;
                ctx().state().setNone();
                return JobResult::Done;
            }

            slept_               = true;
            ctx().state().kind   = publication_.kind;
            ctx().state().symbol = symbol_;
            aboutToSleep.store(true, std::memory_order_release);
            aboutToSleep.notify_one();
            if (publishBeforeParking_)
                publish();
            return JobResult::Sleep;
        }

        void publish()
        {
            payload = 42;
            (symbol_->*publication_.publish)(ctx());
        }

        std::atomic<bool> aboutToSleep{false};
        uint32_t          payload   = 0;
        bool              completed = false;

    private:
        Symbol*           symbol_;
        SymbolPublication publication_;
        bool              publishBeforeParking_;
        bool              slept_ = false;
    };

    Result checkSymbolPublication(TaskContext& ctx, bool publishBeforeParking)
    {
        auto& manager = ctx.global().jobMgr();
        for (const auto publication : SYMBOL_PUBLICATIONS)
        {
            Symbol               symbol(nullptr, TokenRef::invalid(), SymbolKind::Constant, IdentifierRef::invalid(), {});
            SymbolPublicationJob job(ctx, symbol, publication, publishBeforeParking);
            manager.enqueue(job, JobPriority::Normal, ctx.compiler().jobClientId());
            manager.waitAll();
            if (!publishBeforeParking)
            {
                job.publish();
                manager.waitAll();
            }

            const bool resumedWithoutBarrier = job.completed;
            // A negative control must drain its sleeper before destroying the job.
            if (job.rec())
            {
                manager.wakeAll(ctx.compiler().jobClientId());
                manager.waitAll();
            }
            if (!resumedWithoutBarrier || job.rec())
                return Result::Error;
        }
        return Result::Continue;
    }

    class TypeInfoOwnerJob final : public Job
    {
    public:
        TypeInfoOwnerJob(const TaskContext& ctx, TypeGen::TypeGenCache& cache, uint32_t& payload, bool releaseBeforeParking = false) :
            Job(ctx, JobKind::Sema),
            cache_(&cache),
            payload_(&payload),
            releaseBeforeParking_(releaseBeforeParking)
        {
        }

        JobResult exec() override
        {
            std::optional<TypeGen::CacheLock> earlierOwner;
            if (releaseBeforeParking_ && attempts == 0)
                earlierOwner.emplace(*cache_, ctx(), TypeGen::LockMode::Wait);
            ++attempts;

            const TypeGen::CacheLock lock(*cache_, ctx(), TypeGen::LockMode::TryLock);
            if (!lock.ownsLock())
            {
                ctx().state().kind               = TaskStateKind::SemaWaitTypeInfoGeneration;
                ctx().state().typeInfoOwner      = &cache_->ownership;
                ctx().state().typeInfoGeneration = lock.generation();
                if (earlierOwner)
                    *payload_ = 42;
                return JobResult::Sleep;
            }

            // This ordinary payload is protected by the same ownership as metadata.
            // A resumed contender must acquire the preceding owner's publication.
            ++*payload_;
            completed = true;
            ctx().state().setNone();
            return JobResult::Done;
        }

        uint32_t attempts  = 0;
        bool     completed = false;

    private:
        TypeGen::TypeGenCache* cache_;
        uint32_t*              payload_;
        bool                   releaseBeforeParking_;
    };

    Result checkTypeInfoOwnershipRelease(TaskContext& ctx, bool beforeParking)
    {
        auto&                               manager = ctx.global().jobMgr();
        TypeGen::TypeGenCache               cache;
        uint32_t                            payload = 0;
        std::unique_ptr<TypeGen::CacheLock> owner;
        if (!beforeParking)
            owner = std::make_unique<TypeGen::CacheLock>(cache, ctx, TypeGen::LockMode::Wait);
        TypeInfoOwnerJob job(ctx, cache, payload, beforeParking);
        manager.enqueue(job, JobPriority::Normal, ctx.compiler().jobClientId());
        manager.waitAll();
        bool valid = beforeParking || (!job.completed && job.attempts == 1);
        if (owner)
        {
            payload = 42;
            owner.reset();
            manager.waitAll();
        }
        valid &= job.completed && job.attempts == 2 && payload == 43;
        if (job.rec())
        {
            manager.wakeAll(ctx.compiler().jobClientId());
            manager.waitAll();
        }
        return valid ? Result::Continue : Result::Error;
    }

    class CountJob final : public Job
    {
    public:
        CountJob(const TaskContext& ctx, std::atomic<uint32_t>& count) :
            Job(ctx, JobKind::Parser),
            count_(&count)
        {
        }

        JobResult exec() override
        {
            count_->fetch_add(1, std::memory_order_relaxed);
            return JobResult::Done;
        }

    private:
        std::atomic<uint32_t>* count_ = nullptr;
    };

    class OwnedForkJob final : public Job
    {
    public:
        OwnedForkJob(const TaskContext& ctx, uint32_t depth, std::atomic<uint32_t>& executed, std::atomic<uint32_t>& destroyed) :
            Job(ctx, JobKind::Parser),
            depth_(depth),
            executed_(&executed),
            destroyed_(&destroyed)
        {
        }

        ~OwnedForkJob() override { destroyed_->fetch_add(1, std::memory_order_relaxed); }

        JobResult exec() override
        {
            executed_->fetch_add(1, std::memory_order_relaxed);
            if (depth_)
            {
                for (uint32_t i = 0; i < 2; ++i)
                {
                    auto* child = ctx().compiler().makeJob<OwnedForkJob>(ctx(), depth_ - 1, *executed_, *destroyed_);
                    owner()->enqueue(*child, JobPriority::Normal, clientId());
                }
            }
            return JobResult::Done;
        }

    private:
        uint32_t               depth_;
        std::atomic<uint32_t>* executed_;
        std::atomic<uint32_t>* destroyed_;
    };

    class ForkJob final : public Job
    {
    public:
        ForkJob(const TaskContext& ctx, uint32_t index, std::atomic<bool>& valid) :
            Job(ctx, JobKind::Parser),
            index_(index),
            valid_(&valid)
        {
        }

        JobResult exec() override
        {
            if (input != index_ + 1)
                valid_->store(false, std::memory_order_relaxed);
            ++runs;
            for (ForkJob* child : children)
            {
                if (!child)
                    continue;
                // This write must be published before another worker executes the child.
                child->input = child->index_ + 1;
                owner()->enqueue(*child, static_cast<JobPriority>(child->index_ % 3), clientId());
            }
            return JobResult::Done;
        }

        ForkJob* children[2]{};
        uint32_t input = 0;
        uint32_t runs  = 0;

    private:
        uint32_t           index_;
        std::atomic<bool>* valid_;
    };
}

SWC_TEST_BEGIN(JobManager_DebugStateReportsSleepingJobs)
{
    CommandLine cmdLine;
    cmdLine.numCores = 1;

    JobManager jobMgr;
    jobMgr.setup(cmdLine);

    const Global      global;
    const TaskContext jobCtx(global, cmdLine);
    const auto        clientId = jobMgr.newClientId();

    SleepOnceJob job(jobCtx);
    jobMgr.enqueue(job, JobPriority::Normal, clientId);
    jobMgr.waitAll(clientId);

    if (!jobMgr.wakeAll(clientId))
        return Result::Error;

    jobMgr.waitAll(clientId);
}
SWC_TEST_END()

SWC_TEST_BEGIN(JobManager_ProgressiveWorkersDrainQueuedJobs)
{
    CommandLine cmdLine;
    cmdLine.numCores = 4;

    JobManager jobMgr;
    jobMgr.setup(cmdLine);
    if (jobMgr.numWorkers() != 4 || jobMgr.isSingleThreaded())
        return Result::Error;

    const Global      global;
    const TaskContext jobCtx(global, cmdLine);
    const auto        clientId = jobMgr.newClientId();

    std::atomic<uint32_t>             count{0};
    std::vector<std::unique_ptr<Job>> jobs;
    for (uint32_t index = 0; index < 16; ++index)
    {
        jobs.push_back(std::make_unique<CountJob>(jobCtx, count));
        jobMgr.enqueue(*jobs.back(), JobPriority::Normal, clientId);
    }

    jobMgr.waitAll(clientId);
    if (count.load(std::memory_order_relaxed) != jobs.size())
        return Result::Error;
}
SWC_TEST_END()

// A targeted wake() on the exact dependency must wake only the matching sleeper, and a
// wake() on a different key must not wake it.
SWC_TEST_BEGIN(JobManager_TargetedWakeByName)
{
    CommandLine cmdLine;
    cmdLine.numCores = 1;

    JobManager jobMgr;
    jobMgr.setup(cmdLine);

    const Global      global;
    const TaskContext jobCtx(global, cmdLine);
    const auto        clientId = jobMgr.newClientId();

    const IdentifierRef nameA{8};
    const IdentifierRef nameB{16};
    SleepOnNameJob      lookupA(jobCtx, nameA, TaskStateKind::SemaWaitIdentifier);
    SleepOnNameJob      implA(jobCtx, nameA, TaskStateKind::SemaWaitImplRegistrations);
    SleepOnNameJob      lookupB(jobCtx, nameB, TaskStateKind::SemaWaitIdentifier);
    jobMgr.enqueue(lookupA, JobPriority::Normal, clientId);
    jobMgr.enqueue(implA, JobPriority::Normal, clientId);
    jobMgr.enqueue(lookupB, JobPriority::Normal, clientId);
    jobMgr.waitAll(clientId);

    std::vector<Job*> waiting;
    jobMgr.waitingJobs(waiting, clientId);
    if (waiting.size() != 3)
        return Result::Error;

    // A symbol named A resumes the lookup of A only, without a barrier.
    jobMgr.wake(WaitKey::name(nameA, TaskStateKind::SemaWaitIdentifier));
    jobMgr.waitAll(clientId);
    jobMgr.waitingJobs(waiting, clientId);
    if (waiting.size() != 2 || std::ranges::find(waiting, &lookupA) != waiting.end())
        return Result::Error;

    jobMgr.wake(WaitKey::name(nameA, TaskStateKind::SemaWaitImplRegistrations));
    jobMgr.wake(WaitKey::name(nameB, TaskStateKind::SemaWaitIdentifier));
    jobMgr.waitAll(clientId);
    jobMgr.waitingJobs(waiting, clientId);
    if (!waiting.empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(JobManager_TargetedWakeBySymbol)
{
    CommandLine cmdLine;
    cmdLine.numCores = 1;

    JobManager jobMgr;
    jobMgr.setup(cmdLine);

    const Global      global;
    const TaskContext jobCtx(global, cmdLine);
    const auto        clientId = jobMgr.newClientId();

    // Two distinct dependency targets.
    Symbol dummyA(nullptr, TokenRef::invalid(), SymbolKind::Constant, IdentifierRef::invalid(), {});
    Symbol dummyB(nullptr, TokenRef::invalid(), SymbolKind::Constant, IdentifierRef::invalid(), {});

    SleepOnSymTypedJob jobA(jobCtx, &dummyA);
    SleepOnSymTypedJob jobB(jobCtx, &dummyB);
    jobMgr.enqueue(jobA, JobPriority::Normal, clientId);
    jobMgr.enqueue(jobB, JobPriority::Normal, clientId);
    jobMgr.waitAll(clientId);

    // Waking an unrelated key must not disturb either sleeper.
    jobMgr.wake({&dummyA, TaskStateKind::SemaWaitSymDeclared});
    jobMgr.waitAll(clientId);

    // Waking A's exact key runs A to completion; B stays parked.
    jobMgr.wake({&dummyA, TaskStateKind::SemaWaitSymTyped});
    jobMgr.waitAll(clientId);

    // Waking B's key drains the last sleeper.
    jobMgr.wake({&dummyB, TaskStateKind::SemaWaitSymTyped});
    jobMgr.waitAll(clientId);
}
SWC_TEST_END()

SWC_TEST_BEGIN(JobManager_ParallelForksDrainEveryClient)
{
    CommandLine cmdLine;
    cmdLine.numCores = ctx.global().jobMgr().isSingleThreaded() ? 1 : ctx.global().jobMgr().numWorkers();
    JobManager jobMgr;
    jobMgr.setup(cmdLine);

    const Global      global;
    const TaskContext jobCtx(global, cmdLine);
    const auto        firstClient  = jobMgr.newClientId();
    const auto        secondClient = jobMgr.newClientId();
    std::atomic<bool> valid{true};

    constexpr uint32_t                    JOBS_PER_CLIENT = 127;
    std::vector<std::unique_ptr<ForkJob>> trees[2];
    for (auto& tree : trees)
    {
        for (uint32_t i = 0; i < JOBS_PER_CLIENT; ++i)
            tree.push_back(std::make_unique<ForkJob>(jobCtx, i, valid));
        for (uint32_t i = 0; i < JOBS_PER_CLIENT / 2; ++i)
        {
            tree[i]->children[0] = tree[2 * i + 1].get();
            tree[i]->children[1] = tree[2 * i + 2].get();
        }
        tree.front()->input = 1;
    }

    // Reuse detached jobs across bursts, with per-client and global barriers while
    // workers both consume and publish work at all three priorities.
    for (uint32_t round = 0; round < 8; ++round)
    {
        jobMgr.enqueue(*trees[0].front(), JobPriority::Normal, firstClient);
        jobMgr.enqueue(*trees[1].front(), JobPriority::High, secondClient);
        jobMgr.waitAll(firstClient);
        for (const auto& job : trees[0])
            if (job->runs != round + 1 || job->rec() || job->owner())
                valid.store(false, std::memory_order_relaxed);

        jobMgr.waitAll();
        for (const auto& job : trees[1])
            if (job->runs != round + 1 || job->rec() || job->owner())
                valid.store(false, std::memory_order_relaxed);
    }

    if (!valid.load(std::memory_order_relaxed))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(JobManager_ParallelTargetedWakePreservesOtherSleepers)
{
    CommandLine cmdLine;
    cmdLine.numCores = ctx.global().jobMgr().isSingleThreaded() ? 1 : ctx.global().jobMgr().numWorkers();
    JobManager jobMgr;
    jobMgr.setup(cmdLine);

    const Global      global;
    const TaskContext jobCtx(global, cmdLine);
    const auto        client     = jobMgr.newClientId();
    Symbol            targets[2] = {
        Symbol(nullptr, TokenRef::invalid(), SymbolKind::Constant, IdentifierRef::invalid(), {}),
        Symbol(nullptr, TokenRef::invalid(), SymbolKind::Constant, IdentifierRef::invalid(), {}),
    };
    std::vector<std::unique_ptr<SleepOnSymTypedJob>> jobs;
    for (uint32_t i = 0; i < 128; ++i)
    {
        jobs.push_back(std::make_unique<SleepOnSymTypedJob>(jobCtx, &targets[i % 2]));
        jobMgr.enqueue(*jobs.back(), JobPriority::Normal, client);
    }
    jobMgr.waitAll();

    std::vector<Job*> sleeping;
    jobMgr.waitingJobs(sleeping, client);
    if (sleeping.size() != jobs.size())
        return Result::Error;

    jobMgr.wake({&targets[0], TaskStateKind::SemaWaitSymTyped});
    jobMgr.waitAll(client);
    jobMgr.waitingJobs(sleeping, client);
    if (sleeping.size() != jobs.size() / 2)
        return Result::Error;
    for (uint32_t i = 0; i < jobs.size(); i += 2)
        if (jobs[i]->rec() || jobs[i]->owner())
            return Result::Error;

    jobMgr.wake({&targets[1], TaskStateKind::SemaWaitSymTyped});
    jobMgr.waitAll();
    jobMgr.waitingJobs(sleeping, client);
    if (!sleeping.empty())
        return Result::Error;
    for (const auto& job : jobs)
        if (job->rec() || job->owner())
            return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(JobManager_ClientAndDependencyWakeIndexesStayConsistent)
{
    CommandLine cmdLine;
    cmdLine.numCores = ctx.global().jobMgr().isSingleThreaded() ? 1 : ctx.global().jobMgr().numWorkers();
    JobManager jobMgr;
    jobMgr.setup(cmdLine);

    const Global                      global;
    const TaskContext                 jobCtx(global, cmdLine);
    const std::array<JobClientId, 3>  clients = {0, jobMgr.newClientId(), jobMgr.newClientId()};
    std::vector<std::unique_ptr<Job>> jobs[3];
    Symbol                            target(nullptr, TokenRef::invalid(), SymbolKind::Constant, IdentifierRef::invalid(), {});
    for (uint32_t i = 0; i < 16; ++i)
    {
        for (uint32_t client = 0; client < clients.size(); ++client)
        {
            if (i % 2)
                jobs[client].push_back(std::make_unique<SleepOnceJob>(jobCtx));
            else
                jobs[client].push_back(std::make_unique<SleepOnSymTypedJob>(jobCtx, &target));
            jobMgr.enqueue(*jobs[client].back(), JobPriority::Normal, clients[client]);
        }
    }
    jobMgr.waitAll();

    bool              valid = true;
    std::vector<Job*> sleeping;
    for (uint32_t client = 0; client < clients.size(); ++client)
    {
        jobMgr.waitingJobs(sleeping, clients[client]);
        if (sleeping.size() != jobs[client].size())
            valid = false;
        else
            for (uint32_t i = 0; i < sleeping.size(); ++i)
                if (sleeping[i] != jobs[client][i].get())
                    valid = false;
    }

    // Removing one client's keyed and wildcard waits must preserve the other
    // clients' links, including records waiting on the same dependency key.
    if (!jobMgr.wakeAll(clients[1]))
        valid = false;
    jobMgr.waitAll();
    jobMgr.waitingJobs(sleeping, clients[1]);
    if (!sleeping.empty())
        valid = false;

    jobMgr.wake({&target, TaskStateKind::SemaWaitSymTyped});
    jobMgr.waitAll();
    for (uint32_t client : {0u, 2u})
    {
        jobMgr.waitingJobs(sleeping, clients[client]);
        if (sleeping.size() != 8)
            valid = false;
    }

    // Zero denotes the default client, not every client.
    if (!jobMgr.wakeAll(0))
        valid = false;
    jobMgr.waitAll();
    jobMgr.waitingJobs(sleeping, clients[2]);
    if (sleeping.size() != 8)
        valid = false;
    if (!jobMgr.wakeAll(clients[2]))
        valid = false;
    jobMgr.waitAll();
    for (uint32_t client = 0; client < clients.size(); ++client)
    {
        if (jobMgr.wakeAll(clients[client]))
            valid = false;
        for (const auto& job : jobs[client])
            if (job->rec() || job->owner())
                valid = false;
    }
    if (!valid)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(JobManager_CompilerOwnsConcurrentForksUntilTeardown)
{
    std::atomic<uint32_t> executed{0};
    std::atomic<uint32_t> destroyed{0};
    bool                  keptAlive = false;
    {
        CompilerInstance compiler(ctx.global(), ctx.cmdLine());
        TaskContext      jobCtx(compiler);
        auto&            jobMgr = ctx.global().jobMgr();
        for (uint32_t i = 0; i < 2; ++i)
        {
            auto* root = compiler.makeJob<OwnedForkJob>(jobCtx, 6, executed, destroyed);
            jobMgr.enqueue(*root, JobPriority::Normal, compiler.jobClientId());
        }
        jobMgr.waitAll(compiler.jobClientId());
        keptAlive = destroyed.load() == 0;
    }
    if (!keptAlive || executed.load() != 254 || destroyed.load() != 254)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(JobManager_CompilerOwnsJobsFromUnregisteredThreads)
{
    constexpr uint32_t    NUM_PRODUCERS = 2;
    constexpr uint32_t    NUM_JOBS      = 128;
    std::atomic<uint32_t> executed{0};
    std::atomic<uint32_t> destroyed{0};
    std::atomic<bool>     valid{true};
    {
        CompilerInstance                       compiler(ctx.global(), ctx.cmdLine());
        const TaskContext                      jobCtx(compiler);
        auto&                                  jobMgr = ctx.global().jobMgr();
        std::barrier                           start(NUM_PRODUCERS + 1);
        std::array<std::thread, NUM_PRODUCERS> producers;
        for (auto& producer : producers)
        {
            producer = std::thread([&] {
                if (jobMgr.currentThreadIndex())
                    valid.store(false);
                start.arrive_and_wait();
                for (uint32_t i = 0; i < NUM_JOBS; ++i)
                {
                    auto* job = compiler.makeJob<OwnedForkJob>(jobCtx, 0, executed, destroyed);
                    jobMgr.enqueue(*job, JobPriority::Normal, compiler.jobClientId());
                }
            });
        }
        start.arrive_and_wait();
        for (auto& producer : producers)
            producer.join();
        jobMgr.waitAll(compiler.jobClientId());
        if (destroyed.load())
            valid.store(false);
    }
    if (!valid.load() || executed.load() != NUM_PRODUCERS * NUM_JOBS || destroyed.load() != executed.load())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(JobManager_SymbolPublicationBeforeParkingResumesWithoutBarrier)
{
    SWC_RESULT(checkSymbolPublication(ctx, true));
}
SWC_TEST_END()

SWC_TEST_BEGIN(JobManager_SymbolPublicationAfterParkingResumesWithoutBarrier)
{
    SWC_RESULT(checkSymbolPublication(ctx, false));
}
SWC_TEST_END()

SWC_TEST_BEGIN(JobManager_ConcurrentSymbolPublicationDoesNotLoseWaiters)
{
    constexpr uint32_t                                 NUM_JOBS = 512;
    auto&                                              manager  = ctx.global().jobMgr();
    std::vector<std::unique_ptr<Symbol>>               symbols;
    std::vector<std::unique_ptr<SymbolPublicationJob>> jobs;
    for (uint32_t index = 0; index < NUM_JOBS; ++index)
    {
        symbols.push_back(std::make_unique<Symbol>(nullptr, TokenRef::invalid(), SymbolKind::Constant, IdentifierRef::invalid(), SymbolFlags{}));
        jobs.push_back(std::make_unique<SymbolPublicationJob>(ctx, *symbols.back(), SYMBOL_PUBLICATIONS[index % std::size(SYMBOL_PUBLICATIONS)], false));
    }

    std::thread producer([&] {
        for (const auto& job : jobs)
        {
            job->aboutToSleep.wait(false, std::memory_order_acquire);
            job->publish();
        }
    });
    for (const auto& job : jobs)
        manager.enqueue(*job, JobPriority::Normal, ctx.compiler().jobClientId());
    manager.waitAll();
    producer.join();
    manager.waitAll();

    bool valid = true;
    for (const auto& job : jobs)
        if (!job->completed || job->rec())
            valid = false;
    manager.wakeAll(ctx.compiler().jobClientId());
    manager.waitAll();
    if (!valid)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(JobManager_TypeInfoReleaseBeforeParkingResumesWithoutBarrier)
{
    SWC_RESULT(checkTypeInfoOwnershipRelease(ctx, true));
}
SWC_TEST_END()

SWC_TEST_BEGIN(JobManager_TypeInfoReleaseAfterParkingResumesWithoutBarrier)
{
    SWC_RESULT(checkTypeInfoOwnershipRelease(ctx, false));
}
SWC_TEST_END()

SWC_TEST_BEGIN(JobManager_TypeInfoReleaseWakesOnlyItsStorage)
{
    auto&                 manager = ctx.global().jobMgr();
    TypeGen::TypeGenCache firstCache;
    TypeGen::TypeGenCache secondCache;
    uint32_t              firstPayload  = 42;
    uint32_t              secondPayload = 42;
    auto                  firstOwner    = std::make_unique<TypeGen::CacheLock>(firstCache, ctx, TypeGen::LockMode::Wait);
    auto                  secondOwner   = std::make_unique<TypeGen::CacheLock>(secondCache, ctx, TypeGen::LockMode::Wait);
    TypeInfoOwnerJob      first(ctx, firstCache, firstPayload);
    TypeInfoOwnerJob      second(ctx, secondCache, secondPayload);
    manager.enqueue(first, JobPriority::Normal, ctx.compiler().jobClientId());
    manager.enqueue(second, JobPriority::Normal, ctx.compiler().jobClientId());
    manager.waitAll();
    firstOwner.reset();
    manager.waitAll();
    bool valid = first.completed && first.attempts == 2 && firstPayload == 43 &&
                 !second.completed && second.attempts == 1 && secondPayload == 42;
    secondOwner.reset();
    manager.waitAll();
    valid &= second.completed && second.attempts == 2 && secondPayload == 43;
    manager.wakeAll(ctx.compiler().jobClientId());
    manager.waitAll();
    if (!valid || first.rec() || second.rec())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(JobManager_TypeInfoContendersPreserveExclusivePublication)
{
    constexpr uint32_t                             NUM_JOBS = 256;
    auto&                                          manager  = ctx.global().jobMgr();
    TypeGen::TypeGenCache                          cache;
    uint32_t                                       payload = 0;
    auto                                           owner   = std::make_unique<TypeGen::CacheLock>(cache, ctx, TypeGen::LockMode::Wait);
    std::vector<std::unique_ptr<TypeInfoOwnerJob>> jobs;
    for (uint32_t index = 0; index < NUM_JOBS; ++index)
    {
        jobs.push_back(std::make_unique<TypeInfoOwnerJob>(ctx, cache, payload));
        manager.enqueue(*jobs.back(), JobPriority::Normal, ctx.compiler().jobClientId());
    }
    // All contenders yield even though the resource remains owned by this thread.
    manager.waitAll();
    bool valid = payload == 0;
    for (const auto& job : jobs)
        valid &= job->attempts == 1 && !job->completed;
    owner.reset();
    manager.waitAll();
    valid &= payload == NUM_JOBS;
    for (const auto& job : jobs)
        valid &= job->completed && !job->rec();
    manager.wakeAll(ctx.compiler().jobClientId());
    manager.waitAll();
    if (!valid)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
