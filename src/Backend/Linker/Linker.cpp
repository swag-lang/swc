#include "pch.h"
#include "Backend/Linker/Linker.h"
#include "Backend/Linker/ImageWriter.PE.h"
#include "Backend/Linker/Linker.ELF.h"
#include "Backend/Linker/Linker.PE.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Main/Command/CommandLine.h"
#include "Main/FileSystem.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // Writes the produced bytes through the shared FileSystem helper, recording a ready-to-report
    // diagnostic on the job if the write fails (finishLink reports it on the foreground thread).
    bool writeJobArtifact(LinkJob& job, const fs::path& path, const ByteArray& bytes)
    {
        FileSystem::IoErrorInfo ioError;
        if (FileSystem::writeBinaryFileAtomic(path, bytes.data(), bytes.size(), ioError) != Result::Continue)
        {
            job.error = Diagnostic::get(DiagnosticId::cmd_err_link_artifact_write_failed);
            job.error.addArgument(Diagnostic::ARG_PATH, Utf8(path));

            // Windows locks a running image, so the usual cause here is a previous run of this
            // very artifact still alive; naming the process is what makes the failure actionable.
            job.error.addArgument(Diagnostic::ARG_BECAUSE, FileSystem::appendFileUsers(FileSystem::describeIoFailure(ioError), path));
            return false;
        }

        return true;
    }

    void publishIncrementalCache(LinkJob& job)
    {
        for (LinkJob::IncrementalObject& object : job.incrementalCacheFiles)
        {
            // Another linker may still be reading the previous cache entry.
            std::error_code ec;
            fs::create_directories(object.path.parent_path(), ec);
            if (ec)
                return;

            FileSystem::IoErrorInfo ioError;
            if (FileSystem::writeBinaryFileAtomic(object.path, object.bytes.data(), object.bytes.size(), ioError, FileSystem::FileReplacement::Mapped) != Result::Continue)
                return;
        }
        job.incrementalCacheFiles.clear();
    }

    // Build and publish the artifact, leaving a diagnostic in job.error on failure.
    // executePreparedLink records the outcome in job.ok.
    bool writePeExecutable(LinkJob& job)
    {
        PEWriter  writer;
        ByteArray bytes;
        ByteArray pdbBytes;
        if (!writer.writeImage(bytes, pdbBytes, job.error, job.image, job.debugInfo, job.pdbPath))
            return false;
        if (!writeJobArtifact(job, job.outputPath, bytes))
            return false;

        // Replace the PDB when generated; otherwise remove debug data from an earlier build.
        if (!pdbBytes.empty() && !writeJobArtifact(job, job.pdbPath, pdbBytes))
            return false;

        if (pdbBytes.empty())
        {
            fs::path stalePdbPath = job.pdbPath;
            if (stalePdbPath.empty() && !job.outputPath.empty())
            {
                stalePdbPath = job.outputPath;
                stalePdbPath.replace_extension(".pdb");
            }

            if (!stalePdbPath.empty())
            {
                std::error_code ec;
                fs::remove(stalePdbPath, ec);
                if (ec)
                {
                    job.error = Diagnostic::get(DiagnosticId::cmd_err_link_artifact_write_failed);
                    job.error.addArgument(Diagnostic::ARG_PATH, Utf8(stalePdbPath));
                    job.error.addArgument(Diagnostic::ARG_BECAUSE, FileSystem::appendFileUsers(FileSystem::normalizeSystemMessage(ec), stalePdbPath));
                    return false;
                }
            }
        }

        publishIncrementalCache(job);

        return true;
    }

    // The prepared job owns all state, including target selection, so a detached
    // background thread can write the artifact without touching the builder.
    void executePreparedLink(LinkJob& job)
    {
        if (job.targetOs == Runtime::TargetOs::Linux)
        {
            ELFLinker::execute(job);
            if (job.ok)
                publishIncrementalCache(job);
            return;
        }
        SWC_ASSERT(job.targetOs == Runtime::TargetOs::Windows);
        job.ok = writePeExecutable(job);
    }
}

Linker::Linker(NativeBackendBuilder& builder) :
    builder_(&builder)
{
}

std::unique_ptr<Linker> Linker::create(NativeBackendBuilder& builder)
{
    switch (builder.ctx().cmdLine().targetOs)
    {
        case Runtime::TargetOs::Linux:
            return std::make_unique<ELFLinker>(builder);
        case Runtime::TargetOs::Windows:
            return std::make_unique<PELinker>(builder);
    }

    SWC_UNREACHABLE();
}

Os::WindowsToolchainDiscoveryResult Linker::queryToolchainPaths(const NativeBackendBuilder& builder, Os::WindowsToolchainPaths& outToolchain)
{
    switch (builder.ctx().cmdLine().targetOs)
    {
        case Runtime::TargetOs::Windows:
            outToolchain = {};
            return Os::discoverWindowsToolchainPaths(outToolchain);
        default:
            SWC_UNREACHABLE();
    }
}

Result Linker::link()
{
    LinkJob job;
    SWC_RESULT(prepareLink(job));
    executeLink(job);
    return finishLink(job);
}

void Linker::executeLink(LinkJob& job)
{
    job.executed = true;
    executePreparedLink(job);
}

Result Linker::finishLink(const LinkJob& job) const
{
    SWC_ASSERT(builder_ != nullptr);
    SWC_ASSERT(job.executed);

    if (!job.ok)
        return builder_->reportError(job.error);
    if (!fs::exists(builder_->artifactPath))
        return builder_->reportError(DiagnosticId::cmd_err_native_artifact_missing, Diagnostic::ARG_PATH, Utf8(builder_->artifactPath));

    return Result::Continue;
}

SWC_END_NAMESPACE();
