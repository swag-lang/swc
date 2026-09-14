#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Thread/JobManager.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class RestoreCommandMetrics
    {
    public:
        RestoreCommandMetrics()
        {
            for (size_t index = 0; index < fields_.size(); ++index)
                saved_[index] = (Stats::get().*fields_[index]).load(std::memory_order_relaxed);
        }

        ~RestoreCommandMetrics()
        {
            for (size_t index = 0; index < fields_.size(); ++index)
                (Stats::get().*fields_[index]).store(saved_[index], std::memory_order_relaxed);
        }

    private:
        static constexpr std::array        fields_ = {&Stats::numErrors, &Stats::numWarnings, &Stats::numFiles, &Stats::numTests, &Stats::numTestsFailed, &Stats::numTokens, &Stats::numFormatRewrittenFiles};
        std::array<size_t, fields_.size()> saved_{};
    };

    class DiagnosticFreeFailureJob final : public Job
    {
    public:
        DiagnosticFreeFailureJob(const TaskContext& ctx, const bool waitForDiagnostic) :
            Job(ctx, JobKind::Parser),
            waitForDiagnostic_(waitForDiagnostic)
        {
            this->ctx().setMuteOutput(true);
        }

        JobResult exec() override
        {
            if (cancelled_.load(std::memory_order_acquire))
                return JobResult::Done;

            const bool ready = waitForDiagnostic_ ? ctx().compiler().hasErrorDiagnostic() : ctx().compiler().mainFunc() != nullptr;
            if (!ready)
            {
                // The first run may precede CompilerInstance::run and its metrics reset.
                // Sleep until real sema publication, then let its normal progress wake us.
                // No worker is blocked and the test does not reconfigure the global pool.
                ctx().state().kind = TaskStateKind::SemaWaitIdentifier;
                return JobResult::Sleep;
            }

            ctx().state().setNone();
            failedWithCleanContext_ = !ctx().hasError() && !ctx().silentDiagnostic();
            returnedFailure_        = true;
            return toJobResult(ctx(), Result::Error);
        }

        void cancel() { cancelled_.store(true, std::memory_order_release); }
        bool returnedFailure() const { return returnedFailure_; }
        bool failedWithCleanContext() const { return failedWithCleanContext_; }

    private:
        bool              waitForDiagnostic_      = false;
        bool              returnedFailure_        = false;
        bool              failedWithCleanContext_ = false;
        std::atomic<bool> cancelled_              = false;
    };

    Result runFailureDriverTest(const TaskContext& ctx, const bool expectedDiagnostic)
    {
        RestoreCommandMetrics restoreMetrics;
        const fs::path        sourcePath = Unittest::makeTestSourcePath("Compiler", expectedDiagnostic ? "ExpectedJobFailure" : "SilentJobFailure");

        CommandLine command;
        command.command  = CommandKind::Sema;
        command.name     = expectedDiagnostic ? "compiler_expected_job_failure" : "compiler_silent_job_failure";
        command.silent   = true;
        command.numCores = 6;
        command.files.insert(sourcePath);
        CommandLineParser::refreshBuildCfg(command);
        // refreshBuildCfg derives this flag from the command kind. This fixture runs the
        // semantic driver while explicitly verifying its source diagnostic expectations.
        command.sourceDrivenTest = expectedDiagnostic;

        CompilerInstance       compiler(ctx.global(), command);
        const std::string_view source = expectedDiagnostic ? "#global private\n#main {}\nfunc rejected()\n{\n    late var value: *s32 // swc-expected-error {{sema_err_late_not_field}}\n}\n" : "#global private\n#main {}\n";
        Unittest::registerTestSource(compiler, sourcePath, source);

        TaskContext              compilerCtx(compiler);
        DiagnosticFreeFailureJob failure(compilerCtx, expectedDiagnostic);
        JobManager&              jobs = ctx.global().jobMgr();
        jobs.enqueue(failure, JobPriority::Normal, compiler.jobClientId());

        const ExitCode exitCode = compiler.run();
        const uint64_t errors   = Stats::getNumErrors();
        // Drain even a failed setup before the stack-owned job or its compiler is destroyed.
        failure.cancel();
        jobs.wakeAll(compiler.jobClientId());
        jobs.waitAll(compiler.jobClientId());

        if (!compiler.mainFunc() || !failure.returnedFailure() || !failure.failedWithCleanContext())
            return Result::Error;
        if (!compiler.hasErrorDiagnostic())
            return Result::Error;
        if (expectedDiagnostic)
            return exitCode == ExitCode::Success && errors == 0 ? Result::Continue : Result::Error;
        return exitCode == ExitCode::CompileError && errors == 1 ? Result::Continue : Result::Error;
    }
}

SWC_TEST_BEGIN(Compiler_SilentJobFailureAfterMainDeclarationFailsTheDriver)
{
    return runFailureDriverTest(ctx, false);
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_ExpectedSourceDiagnosticDoesNotBecomeSilentJobFailure)
{
    return runFailureDriverTest(ctx, true);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
