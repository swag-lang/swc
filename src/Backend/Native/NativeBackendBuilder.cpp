#include "pch.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeLinker.h"
#include "Backend/Native/NativeObjJob.h"
#include "Backend/Native/NativeObjectFileWriter.h"
#include "Backend/Native/NativeSymbolCollector.h"

SWC_BEGIN_NAMESPACE();

NativeBackendBuilder::NativeBackendBuilder(CompilerInstance& compiler, const bool runArtifact) :
    ctx_(compiler),
    compiler_(compiler),
    runArtifact_(runArtifact)
{
}

Result NativeBackendBuilder::run()
{
    if (!validateHost())
        return Result::Error;

    NativeSymbolCollector symbolCollector(*this);
    if (!symbolCollector.prepare())
        return Result::Error;

    const NativeArtifactBuilder artifactBuilder(*this);
    if (!artifactBuilder.build())
        return Result::Error;
    if (!writeObjects())
        return Result::Error;

    const auto linker = NativeLinker::create(*this);
    if (!linker)
        return reportError("native linker is not implemented for this target OS") ? Result::Continue : Result::Error;
    if (!linker->link())
        return Result::Error;

    if (runArtifact_ && compiler_.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable)
    {
        if (!runGeneratedArtifact())
            return Result::Error;
    }

    return Result::Continue;
}

bool NativeBackendBuilder::writeObject(const uint32_t objIndex)
{
    if (objIndex >= state_.objectDescriptions.size())
        return reportError("native backend object job index is out of range");

    const auto objectWriter = NativeObjectFileWriter::create(*this);
    if (!objectWriter)
        return reportError("native object file writer is not implemented for this target OS");
    return objectWriter->writeObjectFile(state_.objectDescriptions[objIndex]);
}

TaskContext& NativeBackendBuilder::ctx()
{
    return ctx_;
}

const TaskContext& NativeBackendBuilder::ctx() const
{
    return ctx_;
}

CompilerInstance& NativeBackendBuilder::compiler()
{
    return compiler_;
}

const CompilerInstance& NativeBackendBuilder::compiler() const
{
    return compiler_;
}

NativeBackendState& NativeBackendBuilder::state()
{
    return state_;
}

const NativeBackendState& NativeBackendBuilder::state() const
{
    return state_;
}

bool NativeBackendBuilder::validateHost() const
{
    switch (ctx_.cmdLine().targetOs)
    {
        case Runtime::TargetOs::Windows:
            break;

        case Runtime::TargetOs::Linux:
            return reportError("native backend object/link emission is only implemented for Windows targets");

        default:
            return reportError("native backend does not support this target OS");
    }

    if (ctx_.cmdLine().targetArch != Runtime::TargetArch::X86_64)
        return reportError("native backend only supports x86_64 targets");
    if (compiler_.buildCfg().backendKind == Runtime::BuildCfgBackendKind::None)
        return reportError("native backend requires an executable, library, or export backend kind");
    if (compiler_.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable &&
        compiler_.buildCfg().backendSubKind != Runtime::BuildCfgBackendSubKind::Default &&
        compiler_.buildCfg().backendSubKind != Runtime::BuildCfgBackendSubKind::Console)
    {
        return reportError("native backend only supports console executables");
    }

    return true;
}

bool NativeBackendBuilder::writeObjects()
{
    state_.objWriteFailed.store(false, std::memory_order_release);

    JobManager& jobMgr = ctx_.global().jobMgr();
    for (uint32_t i = 0; i < state_.objectDescriptions.size(); ++i)
    {
        auto* job = heapNew<NativeObjJob>(ctx_, *this, i);
        jobMgr.enqueue(*job, JobPriority::Normal, compiler_.jobClientId());
    }

    jobMgr.waitAll(compiler_.jobClientId());
    return !state_.objWriteFailed.load(std::memory_order_acquire);
}

bool NativeBackendBuilder::runGeneratedArtifact() const
{
    uint32_t   exitCode = 0;
    const auto result   = Os::runProcess(exitCode, state_.artifactPath, {}, state_.workDir);
    switch (result)
    {
        case Os::ProcessRunResult::Ok:
            break;

        case Os::ProcessRunResult::StartFailed:
            return reportError(std::format("cannot start [{}]: {}", makeUtf8(state_.artifactPath), Os::systemError()));

        case Os::ProcessRunResult::WaitFailed:
            return reportError(std::format("waiting for [{}] failed", makeUtf8(state_.artifactPath)));

        case Os::ProcessRunResult::ExitCodeFailed:
            return reportError(std::format("cannot get exit code for [{}]: {}", makeUtf8(state_.artifactPath), Os::systemError()));
    }

    if (exitCode != 0)
        return reportError(std::format("generated executable exited with code {}", exitCode));
    return true;
}

bool NativeBackendBuilder::reportError(const std::string_view because) const
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_native_backend);
    diag.addArgument(Diagnostic::ARG_BECAUSE, because);
    diag.report(const_cast<TaskContext&>(ctx_));
    return false;
}

SWC_END_NAMESPACE();
