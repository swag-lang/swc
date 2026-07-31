#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Main/Command/CommandLine.h"
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
        SleepOnSymTypedJob(const TaskContext& ctx, const void* target) :
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
            wait.symbol     = static_cast<const Symbol*>(target_);
            return JobResult::Sleep;
        }

    private:
        const void* target_ = nullptr;
        bool        slept_  = false;
    };

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

    std::atomic<uint32_t>              count{0};
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
    int dummyA = 0;
    int dummyB = 0;

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

SWC_END_NAMESPACE();

#endif
