#include "pch.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeLinker.h"
#include "Backend/Native/NativeObjFileWriter.h"
#include "Backend/Native/NativeObjJob.h"
#include "Backend/Native/NativeSymbolCollector.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void logArtifactAction(const TaskContext& ctx, std::string_view action, const fs::path& artifactPath)
    {
        const Logger::ScopedLock loggerLock(ctx.global().logger());
        Logger::printAction(ctx, action, FileSystem::toUtf8Path(artifactPath.filename()));
    }
}

NativeBackendBuilder::NativeBackendBuilder(CompilerInstance& compiler, const bool runArtifact) :
    ctx_(compiler),
    compiler_(compiler),
    runArtifact_(runArtifact)
{
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
    logArtifactAction(ctx_, "Build", artifactPath);

    if (runArtifact_ && compiler_.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable)
        SWC_RESULT_VERIFY(runGeneratedArtifact());

    return Result::Continue;
}

Result NativeBackendBuilder::writeObject(const uint32_t objIndex)
{
    SWC_ASSERT(objIndex < objectDescriptions.size());
    const auto objectWriter = NativeObjFileWriter::create(*this);
    if (!objectWriter)
        return reportError(DiagnosticId::cmd_err_native_object_writer_not_implemented);
    return objectWriter->writeObjectFile(objectDescriptions[objIndex]);
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

Result NativeBackendBuilder::validateTarget() const
{
    const CommandLine& commandLine = ctx_.cmdLine();
    if (commandLine.targetOs != Runtime::TargetOs::Windows)
    {
        return reportError(DiagnosticId::cmd_err_native_target_os_not_supported);
    }

    if (commandLine.targetArch != Runtime::TargetArch::X86_64)
    {
        return reportError(DiagnosticId::cmd_err_native_target_arch_not_supported);
    }

    const Runtime::BuildCfg& buildCfg = compiler_.buildCfg();
    if (buildCfg.backendKind == Runtime::BuildCfgBackendKind::None)
    {
        return reportError(DiagnosticId::cmd_err_native_backend_kind_required);
    }

    if (buildCfg.backendKind == Runtime::BuildCfgBackendKind::Executable &&
        buildCfg.backendSubKind != Runtime::BuildCfgBackendSubKind::Default &&
        buildCfg.backendSubKind != Runtime::BuildCfgBackendSubKind::Console)
    {
        return reportError(DiagnosticId::cmd_err_native_executable_subsystem_not_supported);
    }

    return Result::Continue;
}

Result NativeBackendBuilder::writeObjects()
{
    objWriteFailed.store(false, std::memory_order_release);

    JobManager& jobMgr = ctx_.global().jobMgr();
    for (uint32_t i = 0; i < objectDescriptions.size(); ++i)
    {
        auto* job = heapNew<NativeObjJob>(ctx_, *this, i);
        jobMgr.enqueue(*job, JobPriority::Normal, compiler_.jobClientId());
    }

    jobMgr.waitAll(compiler_.jobClientId());
    return objWriteFailed.load(std::memory_order_acquire) ? Result::Error : Result::Continue;
}

Result NativeBackendBuilder::runGeneratedArtifact() const
{
    logArtifactAction(ctx_, "Run", artifactPath);

    uint32_t   exitCode = 0;
    const auto result   = Os::runProcess(exitCode, artifactPath, {}, workDir);
    switch (result)
    {
        case Os::ProcessRunResult::Ok:
            break;
        case Os::ProcessRunResult::StartFailed:
            return reportError(DiagnosticId::cmd_err_native_artifact_start_failed, Diagnostic::ARG_PATH, FileSystem::toUtf8Path(artifactPath), Diagnostic::ARG_BECAUSE, Os::systemError());
        case Os::ProcessRunResult::WaitFailed:
            return reportError(DiagnosticId::cmd_err_native_artifact_wait_failed, Diagnostic::ARG_PATH, FileSystem::toUtf8Path(artifactPath));
        case Os::ProcessRunResult::ExitCodeFailed:
            return reportError(DiagnosticId::cmd_err_native_artifact_exit_code_failed, Diagnostic::ARG_PATH, FileSystem::toUtf8Path(artifactPath), Diagnostic::ARG_BECAUSE, Os::systemError());
    }

    if (exitCode != 0)
        return reportError(DiagnosticId::cmd_err_native_artifact_failed, Diagnostic::ARG_VALUE, exitCode);
    return Result::Continue;
}

SWC_END_NAMESPACE();
