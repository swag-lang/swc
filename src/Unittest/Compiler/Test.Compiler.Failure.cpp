#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Os/Os.h"
#include "Support/Thread/JobManager.h"
#include "Unittest/Compiler/CompilerTestFile.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class RecoveryTestDirectory
    {
    public:
        RecoveryTestDirectory()
        {
            path_ = (Os::getTemporaryPath() / "swc_unittest" / "error_recovery" / std::format("p{}", Os::currentProcessId())).lexically_normal();
            std::error_code ec;
            fs::remove_all(path_, ec);
        }

        ~RecoveryTestDirectory()
        {
            std::error_code ec;
            fs::remove_all(path_, ec);
        }

        const fs::path& path() const { return path_; }

    private:
        fs::path path_;
    };

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

SWC_TEST_BEGIN(Compiler_DependentFailureWhileSourceDiagnosticIsBeingBuilt)
{
    RestoreCommandMetrics restoreMetrics;
    const fs::path        sourcePath = Unittest::makeTestSourcePath("Compiler", "PendingSourceDiagnostic");
    CommandLine           command;
    command.command  = CommandKind::Sema;
    command.name     = "compiler_pending_source_diagnostic";
    command.silent   = true;
    command.numCores = 6;
    command.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(command);

    CompilerInstance compiler(ctx.global(), command);
    Unittest::registerTestSource(compiler, sourcePath, "#global private\n#main {}\n");
    if (compiler.run() != ExitCode::Success || !compiler.mainFunc())
        return Result::Error;

    SourceFile* sourceFile = nullptr;
    for (SourceFile* file : compiler.files())
    {
        if (file->path() == sourcePath)
            sourceFile = file;
    }
    if (!sourceFile)
        return Result::Error;

    TaskContext compilerCtx(compiler);
    compilerCtx.setMuteOutput(true);
    Sema       sema(compilerCtx, sourceFile->nodePayloadContext(), false);
    const auto functionView = sema.viewStored(compiler.mainFunc()->nodeRef(sourceFile->ast()));
    if (!functionView.hasSymbol())
        return Result::Error;
    auto* function = functionView.sym()->safeCast<SymbolFunction>();
    if (!function)
        return Result::Error;
    sema.frame().setCurrentFunction(function);

    // A speculative failure must neither poison the function nor publish an error.
    compilerCtx.setSilentDiagnostic(true);
    SemaError::report(sema, DiagnosticId::sema_err_late_not_field, function->codeRef());
    if (function->isIgnored() || compiler.hasErrorDiagnostic())
        return Result::Error;
    compilerCtx.setSilentDiagnostic(false);

    const auto diagnostic = SemaError::report(sema, DiagnosticId::sema_err_late_not_field, function->codeRef());
    if (!function->isIgnored())
        return Result::Error;

    // Hold the diagnostic before rendering it while another worker observes the failed
    // function. That dependent error must not invent a second, internal diagnostic.
    TaskContext              dependentCtx(compiler);
    DiagnosticFreeFailureJob failure(dependentCtx, false);
    JobManager&              jobs = ctx.global().jobMgr();
    jobs.enqueue(failure, JobPriority::Normal, compiler.jobClientId());
    jobs.waitAll(compiler.jobClientId());
    if (!failure.returnedFailure() || !failure.failedWithCleanContext() || Stats::getNumErrors() != 0)
        return Result::Error;

    diagnostic.report(compilerCtx);
    return compiler.hasErrorDiagnostic() && Stats::getNumErrors() == 1 ? Result::Continue : Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_ExpectedSourceDiagnosticDoesNotBecomeSilentJobFailure)
{
    return runFailureDriverTest(ctx, true);
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Compiler_NativePanicReleasesCapturedErrorsBeforeRecovery)
{
    const RecoveryTestDirectory directory;
    for (const bool switchContext : {false, true})
    {
        std::string source = "#global private\n";
        source += switchContext ? "const SwitchContext = true\n" : "const SwitchContext = false\n";
        source += R"SWAG(
var recoveryDrops: [16] Swag.AtomicValue'u32
var recoveryGeneration: u32
var recoveryContext: *Swag.Context?

struct RecoveryError { generation: u32 }
impl RecoveryError
{
    mtd opPostCopy() { .generation += 1 }
    mtd opDrop() { recoveryDrops[.generation].add(1) }
}

func failRecoveryError() fail
{
    fail RecoveryError{}
}

func failRecoveryPanic() fail
{
    fail Swag.BaseError{"intentional first-test panic with a live captured error"}
}

#[Swag.Safety(.All, false)]
#test
{
    let previous = Swag.getContext()
    defer Swag.setContext(previous)
    recoveryContext = previous
    var local: Swag.Context
    if SwitchContext
    {
        local.allocator = previous.allocator
        local.defaultAllocator = previous.defaultAllocator
        local.runtimeFlags = previous.runtimeFlags
        local.panic = previous.panic
        Swag.setContext(local)
    }
    catch failRecoveryError() as error
    if error is RecoveryError as value do
        recoveryGeneration = value.generation
    expect failRecoveryPanic()
}

#test
{
    let context = Swag.getContext()
    Swag.assert(context == recoveryContext)
    Swag.assert(context.errorCaptures == null)
    Swag.assert(context.errorIndex == 0 and context.hasError == 0 and context.curError == null)
    Swag.assert(recoveryDrops[recoveryGeneration].load() == 1)
    catch failRecoveryError() as error
    Swag.assert((error is RecoveryError))
    Swag.print("captured error recovery completed\n")
}
)SWAG";
        const fs::path caseDirectory = directory.path() / (switchContext ? "local_context" : "runner_context");
        const fs::path sourcePath    = caseDirectory / "recovery.swg";
        SWC_RESULT(CompilerTestFile::writeText(sourcePath, source));
        const std::vector<Utf8> args = {
            "test",
            "--file",
            Utf8(sourcePath),
            "--out-dir",
            Utf8(caseDirectory / "output"),
            "--work-dir",
            Utf8(caseDirectory / "work"),
            "--build-cfg",
            "devmode",
            "--no-test-jit",
            "--num-cores",
            "1",
            "--no-log-color",
        };
        std::string                 output;
        uint32_t                    exitCode = UINT32_MAX;
        const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false, .timeoutMs = 30000};
        const auto                  result = Os::runProcess(exitCode, Os::getExeFullName(), args, caseDirectory, &options);
        // The first panic is intentional. The second native test must run on a clean context,
        // observe the captured payload's destruction, and handle a new error normally.
        if (result != Os::ProcessRunResult::Ok || exitCode == 0 ||
            output.find("intentional first-test panic with a live captured error") == std::string::npos ||
            output.find("captured error recovery completed") == std::string::npos ||
            output.find("generated executable '#test' result: 1 did not pass") == std::string::npos ||
            output.find("hardware exception") != std::string::npos)
        {
            std::println(stderr, "[native panic recovery, local context={}] {}", switchContext, output);
            return Result::Error;
        }
    }
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Compiler_ExpectTerminatesWithReturningPanicHook)
{
    const RecoveryTestDirectory directory;
    for (const std::string_view configuration : {"devmode", "release"})
    {
        const fs::path caseDirectory = directory.path() / configuration;
        const fs::path sourcePath    = caseDirectory / "expect.swg";
        SWC_RESULT(CompilerTestFile::writeText(sourcePath, R"SWAG(
#global private

func failValue()->s32 fail { fail Swag.BaseError{"terminal expect"} }
func hook(message: string?, location: Swag.SourceCodeLocation)
{
    if message == null or location.lineStart == 0 do return
    discard catch failValue() as error
    if error != null do Swag.print("expect hook observed the error\n")
}

#[Swag.Safety(.All, false)]
#test
{
    if Swag.jit() do return
    Swag.getContext().panic = &hook
    discard expect failValue()
    Swag.print("expect resumed after failure\n")
}
)SWAG"));
        const std::vector<Utf8> args = {
            "test",
            "--file",
            Utf8(sourcePath),
            "--out-dir",
            Utf8(caseDirectory / "output"),
            "--work-dir",
            Utf8(caseDirectory / "work"),
            "--build-cfg",
            Utf8(configuration),
            "--no-test-jit",
            "--num-cores",
            "1",
            "--no-log-color",
        };
        std::string                 output;
        uint32_t                    exitCode = UINT32_MAX;
        const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false, .timeoutMs = 15000};
        const auto                  result = Os::runProcess(exitCode, Os::getExeFullName(), args, caseDirectory, &options);
        if (result != Os::ProcessRunResult::Ok || exitCode == 0 ||
            output.find("expect hook observed the error") == std::string::npos ||
            output.find("expect resumed after failure") != std::string::npos ||
            output.find("hardware exception") != std::string::npos)
        {
            std::println(stderr, "[terminal expect, {}] {}", configuration, output);
            return Result::Error;
        }
    }
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Compiler_TestOwnedTryTerminatesThroughInlineExpansion)
{
    const RecoveryTestDirectory directory;
    for (const bool injection : {false, true})
    {
        const fs::path caseDirectory = directory.path() / (injection ? "injection" : "argument");
        const fs::path sourcePath    = caseDirectory / "expect_inline.swg";
        std::string    source        = R"SWAG(
#global private
#[Swag.NoInline]
func raiseError()->s32 fail { fail Swag.BaseError{"terminal test-owned try"} }
#[Swag.Inline]
func propagate()->s32 fail => try raiseError()
#[Swag.Inline]
func identity(value: s32)->s32 => value
#[Swag.Macro]
func injectStatement(statement: #code) { #inject(statement) }
#[Swag.Safety(.Expect, false)]
#test
{
)SWAG";
        source += injection ? "    injectStatement(#code { discard try propagate() })\n" : "    discard identity(try propagate())\n";
        source += R"SWAG(
    Swag.print("test-owned try resumed\n")
}
#test { Swag.print("test-owned try recovery completed\n") }
)SWAG";
        SWC_RESULT(CompilerTestFile::writeText(sourcePath, source));
        const std::vector<Utf8> args = {
            "test",
            "--file",
            Utf8(sourcePath),
            "--out-dir",
            Utf8(caseDirectory / "output"),
            "--work-dir",
            Utf8(caseDirectory / "work"),
            "--build-cfg",
            "release",
            "--no-test-jit",
            "--num-cores",
            "1",
            "--no-log-color",
        };
        std::string                 output;
        uint32_t                    exitCode = UINT32_MAX;
        const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false, .timeoutMs = 15000};
        const auto                  result = Os::runProcess(exitCode, Os::getExeFullName(), args, caseDirectory, &options);
        if (result != Os::ProcessRunResult::Ok || exitCode == 0 ||
            output.find("terminal test-owned try") == std::string::npos ||
            output.find("test-owned try resumed") != std::string::npos ||
            output.find("test-owned try recovery completed") == std::string::npos ||
            output.find("generated executable '#test' result: 1 did not pass") == std::string::npos ||
            output.find("hardware exception") != std::string::npos)
        {
            std::println(stderr, "[terminal test-owned try, injection={}] {}", injection, output);
            return Result::Error;
        }
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
