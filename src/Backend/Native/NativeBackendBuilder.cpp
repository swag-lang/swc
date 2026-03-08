#include "pch.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeLinker.h"
#include "Backend/Native/NativeObjFileWriter.h"
#include "Backend/Native/NativeObjJob.h"
#include "Backend/Native/NativeSymbolCollector.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"

SWC_BEGIN_NAMESPACE();

NativeBackendBuilder::NativeBackendBuilder(CompilerInstance& compiler, const bool runArtifact) :
    ctx_(compiler),
    compiler_(compiler),
    runArtifact_(runArtifact)
{
}

Result NativeBackendBuilder::run()
{
    SWC_RESULT_VERIFY(validateTarget());

    NativeSymbolCollector symbolCollector(*this);
    SWC_RESULT_VERIFY(symbolCollector.prepare());

    const NativeArtifactBuilder artifactBuilder(*this);
    SWC_RESULT_VERIFY(artifactBuilder.build());
    SWC_RESULT_VERIFY(writeObjects());

    const auto linker = NativeLinker::create(*this);
    if (!linker)
        return reportError(DiagnosticId::cmd_err_native_linker_not_implemented);
    SWC_RESULT_VERIFY(linker->link());

    if (runArtifact_ && compiler_.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable)
        SWC_RESULT_VERIFY(runGeneratedArtifact());

    return Result::Continue;
}

Result NativeBackendBuilder::writeObject(const uint32_t objIndex)
{
    SWC_ASSERT(objIndex < state_.objectDescriptions.size());
    const auto objectWriter = NativeObjFileWriter::create(*this);
    if (!objectWriter)
        return reportError(DiagnosticId::cmd_err_native_object_writer_not_implemented);
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

Result NativeBackendBuilder::validateTarget() const
{
    switch (ctx_.cmdLine().targetOs)
    {
        case Runtime::TargetOs::Windows:
            break;
        default:
            return reportError(DiagnosticId::cmd_err_native_target_os_not_supported);
    }

    if (ctx_.cmdLine().targetArch != Runtime::TargetArch::X86_64)
        return reportError(DiagnosticId::cmd_err_native_target_arch_not_supported);
    if (compiler_.buildCfg().backendKind == Runtime::BuildCfgBackendKind::None)
        return reportError(DiagnosticId::cmd_err_native_backend_kind_required);
    if (compiler_.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable &&
        compiler_.buildCfg().backendSubKind != Runtime::BuildCfgBackendSubKind::Default &&
        compiler_.buildCfg().backendSubKind != Runtime::BuildCfgBackendSubKind::Console)
    {
        return reportError(DiagnosticId::cmd_err_native_executable_subsystem_not_supported);
    }

    return Result::Continue;
}

Result NativeBackendBuilder::writeObjects()
{
    state_.objWriteFailed.store(false, std::memory_order_release);

    JobManager& jobMgr = ctx_.global().jobMgr();
    for (uint32_t i = 0; i < state_.objectDescriptions.size(); ++i)
    {
        auto* job = heapNew<NativeObjJob>(ctx_, *this, i);
        jobMgr.enqueue(*job, JobPriority::Normal, compiler_.jobClientId());
    }

    jobMgr.waitAll(compiler_.jobClientId());
    return state_.objWriteFailed.load(std::memory_order_acquire) ? Result::Error : Result::Continue;
}

Result NativeBackendBuilder::runGeneratedArtifact() const
{
    uint32_t   exitCode = 0;
    const auto result   = Os::runProcess(exitCode, state_.artifactPath, {}, state_.workDir);
    switch (result)
    {
        case Os::ProcessRunResult::Ok:
            break;
        case Os::ProcessRunResult::StartFailed:
            return reportError(DiagnosticId::cmd_err_native_artifact_start_failed, Diagnostic::ARG_PATH, makeUtf8(state_.artifactPath), Diagnostic::ARG_BECAUSE, Os::systemError());
        case Os::ProcessRunResult::WaitFailed:
            return reportError(DiagnosticId::cmd_err_native_artifact_wait_failed, Diagnostic::ARG_PATH, makeUtf8(state_.artifactPath));
        case Os::ProcessRunResult::ExitCodeFailed:
            return reportError(DiagnosticId::cmd_err_native_artifact_exit_code_failed, Diagnostic::ARG_PATH, makeUtf8(state_.artifactPath), Diagnostic::ARG_BECAUSE, Os::systemError());
    }

    if (exitCode != 0)
        return reportError(DiagnosticId::cmd_err_native_artifact_failed, Diagnostic::ARG_VALUE, exitCode);
    return Result::Continue;
}

Result NativeBackendBuilder::reportError(DiagnosticId id) const
{
    return reportError(Diagnostic::get(id));
}

Result NativeBackendBuilder::reportError(const Diagnostic& diag) const
{
    diag.report(const_cast<TaskContext&>(ctx_));
    return Result::Error;
}

SWC_END_NAMESPACE();
