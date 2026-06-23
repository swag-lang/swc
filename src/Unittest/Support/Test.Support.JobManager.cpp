#include "pch.h"

#if SWC_HAS_UNITTEST

#include <sstream>

#include "Main/Command/CommandLine.h"
#include "Main/Global.h"
#include "Support/Report/Logger.h"
#include "Support/Report/ScopedTimedLog.h"
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

    class StdoutCapture
    {
    public:
        explicit StdoutCapture(Logger& logger) :
            unmute_(logger),
            previous_(std::cout.rdbuf(stream_.rdbuf()))
        {
        }

        ~StdoutCapture()
        {
            std::cout.rdbuf(previous_);
        }

        std::string str() const { return stream_.str(); }

    private:
        Logger::ScopedStageOutputUnmute unmute_;
        std::ostringstream stream_;
        std::streambuf*    previous_ = nullptr;
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

SWC_TEST_BEGIN(ScopedTimedLog_CommandHeaderUsesCommandGlyph)
{
    CommandLine cmdLine;
    cmdLine.command  = CommandKind::Run;
    cmdLine.logAscii = true;
    cmdLine.logColor = false;
    cmdLine.buildCfg = "debug";

    const Global      global;
    const TaskContext localCtx(global, cmdLine);
    StdoutCapture     capture(global.logger());
    ScopedTimedLog::printCommandHeader(localCtx);

    const std::string text = capture.str();
    if (!text.starts_with("  >  run"))
        return Result::Error;
    if (text.find("debug") == std::string::npos)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ScopedTimedLog_OutputDisabledWhileMuted)
{
    CommandLine cmdLine;
    cmdLine.command = CommandKind::Build;

    const Global      global;
    const TaskContext localCtx(global, cmdLine);
    if (!ScopedTimedLog::isOutputEnabled(localCtx, ScopedTimedLog::Stage::Build))
        return Result::Error;

    {
        Logger::ScopedStageMute muteNestedStages(global.logger());
        if (ScopedTimedLog::isOutputEnabled(localCtx, ScopedTimedLog::Stage::Build))
            return Result::Error;
    }

    if (!ScopedTimedLog::isOutputEnabled(localCtx, ScopedTimedLog::Stage::Build))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ScopedTimedLog_UpToDateUsesReuseGlyph)
{
    CommandLine cmdLine;
    cmdLine.command  = CommandKind::Build;
    cmdLine.logAscii = true;
    cmdLine.logColor = false;

    const Global      global;
    const TaskContext localCtx(global, cmdLine);
    StdoutCapture     capture(global.logger());
    {
        ScopedTimedLog stage(localCtx, ScopedTimedLog::Stage::Module, "core");
        stage.markUpToDate();
        stage.setStat(ScopedTimedLog::formatStatName(localCtx, "up-to-date"));
    }

    const std::string text = capture.str();
    if (!text.starts_with("  =  Module"))
        return Result::Error;
    if (text.find("up-to-date") == std::string::npos)
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
