#include "pch.h"
#include "Backend/Linker/Linker.h"
#include "Backend/Linker/Archive.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Linker/LinkerPe.h"
#include "Backend/Linker/PeWriter.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // Serialise the LinkImage (or archive the objects) and write the artifact. Runs on a background
    // thread and so touches nothing but the self-contained job.
    void executeInternalLink(LinkJob& job)
    {
        std::vector<std::byte> bytes;
        switch (job.output)
        {
            case LinkJob::Output::Executable:
            case LinkJob::Output::SharedLibrary:
                if (!writePeImage(job.image, bytes, job.errorText))
                {
                    job.ok = false;
                    return;
                }
                break;
            case LinkJob::Output::StaticLibrary:
                if (!buildStaticArchive(job.archiveMembers, bytes, job.errorText))
                {
                    job.ok = false;
                    return;
                }
                break;
        }

        std::ofstream file(job.outputPath, std::ios::binary | std::ios::trunc);
        if (!file.is_open())
        {
            job.errorText = std::format("cannot open '{}' for writing", Utf8(job.outputPath).view());
            job.ok        = false;
            return;
        }
        file.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
        if (!file.good())
        {
            job.errorText = std::format("cannot write '{}'", Utf8(job.outputPath).view());
            job.ok        = false;
            return;
        }
        file.close();

        // A shared library also produces an import library next to it so dependents can link by name.
        if (job.output == LinkJob::Output::SharedLibrary)
        {
            std::vector<Utf8> exportNames;
            exportNames.reserve(job.image.exports.size());
            for (const LinkExport& exported : job.image.exports)
                exportNames.push_back(exported.name);

            std::vector<std::byte> libBytes;
            if (!buildImportLibrary(Utf8(job.outputPath.filename()).view(), exportNames, libBytes, job.errorText))
            {
                job.ok = false;
                return;
            }

            const fs::path libPath = fs::path(job.outputPath).replace_extension(".lib");
            std::ofstream  libFile(libPath, std::ios::binary | std::ios::trunc);
            if (!libFile.is_open())
            {
                job.errorText = std::format("cannot open '{}' for writing", Utf8(libPath).view());
                job.ok        = false;
                return;
            }
            libFile.write(reinterpret_cast<const char*>(libBytes.data()), static_cast<std::streamsize>(libBytes.size()));
            if (!libFile.good())
            {
                job.errorText = std::format("cannot write '{}'", Utf8(libPath).view());
                job.ok        = false;
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
