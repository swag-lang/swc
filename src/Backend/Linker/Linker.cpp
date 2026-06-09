#include "pch.h"
#include "Backend/Linker/Linker.h"
#include "Backend/Linker/Archive.h"
#include "Backend/Linker/LinkerPe.h"
#include "Backend/Linker/PeWriter.h"
#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool writeLinkBytes(Utf8& outError, const fs::path& path, const std::vector<std::byte>& bytes)
    {
        std::ofstream file(path, std::ios::binary | std::ios::trunc);
        if (!file.is_open())
        {
            outError = std::format("cannot open '{}' for writing", Utf8(path).view());
            return false;
        }
        file.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
        if (!file.good())
        {
            outError = std::format("cannot write '{}'", Utf8(path).view());
            return false;
        }
        return true;
    }

    // Serialise the LinkImage (or archive the objects) and write the artifact. Runs on a background
    // thread and so touches nothing but the self-contained job.
    void executeInternalLink(LinkJob& job)
    {
        std::vector<std::byte> bytes;
        switch (job.output)
        {
            case LinkJob::Output::Executable:
            case LinkJob::Output::SharedLibrary:
                if (!writePeImage(bytes, job.errorText, job.image))
                {
                    job.ok = false;
                    return;
                }
                break;
            case LinkJob::Output::StaticLibrary:
                if (!buildStaticArchive(bytes, job.errorText, job.archiveMembers))
                {
                    job.ok = false;
                    return;
                }
                break;
        }

        if (!writeLinkBytes(job.errorText, job.outputPath, bytes))
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
            if (!buildImportLibrary(libBytes, job.errorText, Utf8(job.outputPath.filename()).view(), exportNames))
            {
                job.ok = false;
                return;
            }

            const fs::path libPath = fs::path(job.outputPath).replace_extension(".lib");
            if (!writeLinkBytes(job.errorText, libPath, libBytes))
            {
                job.ok = false;
                return;
            }
        }

        job.ok = true;
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
        case Runtime::TargetOs::Windows:
            return std::make_unique<LinkerPe>(builder);
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
        return builder_->reportError(DiagnosticId::cmd_err_native_link_failed, Diagnostic::ARG_BECAUSE, job.errorText);
    if (!fs::exists(builder_->artifactPath))
        return builder_->reportError(DiagnosticId::cmd_err_native_artifact_missing, Diagnostic::ARG_PATH, Utf8(builder_->artifactPath));
    return Result::Continue;
}

SWC_END_NAMESPACE();
