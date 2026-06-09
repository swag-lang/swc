#include "pch.h"
#include "Backend/Linker/Linker.h"
#include "Backend/Linker/ImageWriter.h"
#include "Backend/Linker/PELinker.h"
#include "Backend/Linker/PEWriter.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Main/FileSystem.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // Writes the produced bytes through the shared FileSystem helper, recording a ready-to-report
    // diagnostic on the job if the write fails (finishLink reports it on the foreground thread).
    bool writeJobArtifact(LinkJob& job, const fs::path& path, const std::vector<std::byte>& bytes)
    {
        FileSystem::IoErrorInfo ioError;
        if (FileSystem::writeBinaryFile(path, bytes.data(), bytes.size(), ioError) != Result::Continue)
        {
            job.error = Diagnostic::get(DiagnosticId::cmd_err_link_artifact_write_failed);
            job.error.addArgument(Diagnostic::ARG_PATH, Utf8(path));
            job.error.addArgument(Diagnostic::ARG_BECAUSE, FileSystem::describeIoFailure(ioError));
            return false;
        }
        return true;
    }

    // Serialise the LinkImage (or archive the objects) and write the artifact. Runs on a background
    // thread and so touches nothing but the self-contained job. The target format is chosen from the
    // job alone (set during prepareLink), so this stays usable on a detached thread.
    void executeInternalLink(LinkJob& job)
    {
        const std::unique_ptr<ImageWriter> writer = ImageWriter::create(job.targetOs);
        SWC_ASSERT(writer != nullptr);

        std::vector<std::byte> bytes;
        switch (job.output)
        {
            case LinkJob::Output::Executable:
            case LinkJob::Output::SharedLibrary:
                if (!writer->writeImage(bytes, job.error, job.image))
                {
                    job.ok = false;
                    return;
                }
                break;
            case LinkJob::Output::StaticLibrary:
                if (!writer->buildStaticArchive(bytes, job.error, job.archiveMembers))
                {
                    job.ok = false;
                    return;
                }
                break;
        }

        if (!writeJobArtifact(job, job.outputPath, bytes))
        {
            job.ok = false;
            return;
        }

        // A shared library also produces an import library next to it so dependents can link by name.
        if (job.output == LinkJob::Output::SharedLibrary)
        {
            std::vector<Utf8> exportNames;
            exportNames.reserve(job.image.exports.size());
            for (const LinkExport& exported : job.image.exports)
                exportNames.push_back(exported.name);

            std::vector<std::byte> libBytes;
            writer->buildImportLibrary(libBytes, Utf8(job.outputPath.filename()).view(), exportNames);

            const fs::path libPath = fs::path(job.outputPath).replace_extension(".lib");
            if (!writeJobArtifact(job, libPath, libBytes))
            {
                job.ok = false;
                return;
            }
        }

        job.ok = true;
    }
}

std::unique_ptr<ImageWriter> ImageWriter::create(const Runtime::TargetOs targetOs)
{
    const auto format = getNativeObjFormat(targetOs);
    SWC_ASSERT(format.has_value());

    switch (*format)
    {
        case NativeObjectFormat::WindowsCoff:
            return std::make_unique<PEWriter>();
    }

    SWC_UNREACHABLE();
}

Linker::Linker(NativeBackendBuilder& builder) :
    builder_(&builder)
{
}

std::unique_ptr<Linker> Linker::create(NativeBackendBuilder& builder)
{
    switch (builder.ctx().cmdLine().targetOs)
    {
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
    executeInternalLink(job);
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
