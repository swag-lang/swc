#include "pch.h"
#include "Backend/Linker/Linker.h"
#include "Backend/Linker/CoffLinker.h"
#include "Backend/Linker/ImageWriter.h"
#include "Backend/Linker/PELinker.h"
#include "Backend/Linker/PEWriter.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Main/FileSystem.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr size_t K_RESPONSE_FILE_COMMAND_LINE_THRESHOLD = 24ull * 1024ull;

    void appendResponseFileArg(Utf8& out, const std::string_view arg)
    {
        const bool needsQuotes = arg.empty() || arg.find_first_of(" \t\r\n\"") != std::string_view::npos;
        if (!needsQuotes)
        {
            out += arg;
            return;
        }

        out += '"';
        size_t pendingSlashes = 0;
        for (const char c : arg)
        {
            if (c == '\\')
            {
                pendingSlashes++;
                continue;
            }

            if (c == '"')
            {
                out.append(pendingSlashes * 2 + 1, '\\');
                out += '"';
                pendingSlashes = 0;
                continue;
            }

            if (pendingSlashes)
            {
                out.append(pendingSlashes, '\\');
                pendingSlashes = 0;
            }

            out += c;
        }

        if (pendingSlashes)
            out.append(pendingSlashes * 2, '\\');
        out += '"';
    }

    Utf8 buildResponseFileContents(const std::vector<Utf8>& args)
    {
        Utf8 contents;
        for (const Utf8& arg : args)
        {
            appendResponseFileArg(contents, arg);
            contents += '\n';
        }

        return contents;
    }

    fs::path responseFilePath(const NativeBackendBuilder& builder, const fs::path& exePath)
    {
        Utf8 name = FileSystem::sanitizeFileName(Utf8(builder.artifactPath.stem()));
        name += ".";
        name += FileSystem::sanitizeFileName(Utf8(exePath.stem()));
        name += ".rsp";
        return builder.buildDir / name.c_str();
    }

    bool shouldUseResponseFile(const fs::path& exePath, const std::vector<Utf8>& args)
    {
        return Os::formatProcessCommandLine(exePath, args).size() >= K_RESPONSE_FILE_COMMAND_LINE_THRESHOLD;
    }

    Result writeResponseFile(NativeBackendBuilder& builder, const fs::path& path, const std::vector<Utf8>& args)
    {
        const Utf8 contents = buildResponseFileContents(args);

        FileSystem::IoErrorInfo ioError;
        if (FileSystem::writeBinaryFile(path, contents.data(), contents.size(), ioError) == Result::Continue)
            return Result::Continue;

        return builder.reportError(DiagnosticId::cmd_err_native_tool_rsp_write_failed, Diagnostic::ARG_PATH, Utf8(path), Diagnostic::ARG_BECAUSE, FileSystem::describeIoFailure(ioError));
    }

    void replayToolOutput(const TaskContext* ctx, const std::string_view output, const std::function<bool(std::string_view)>& lineFilter)
    {
        if (output.empty())
            return;

        size_t lineStart = 0;
        while (lineStart < output.size())
        {
            size_t lineEnd = output.find('\n', lineStart);
            if (lineEnd == std::string_view::npos)
                lineEnd = output.size();
            else
                ++lineEnd;

            std::string_view lineWithEnding = output.substr(lineStart, lineEnd - lineStart);
            std::string_view line           = lineWithEnding;
            if (!line.empty() && line.back() == '\n')
                line.remove_suffix(1);
            if (!line.empty() && line.back() == '\r')
                line.remove_suffix(1);

            if (!lineFilter || lineFilter(line))
            {
                if (ctx)
                    Logger::print(*ctx, lineWithEnding);
                else
                {
                    (void) std::fwrite(lineWithEnding.data(), sizeof(char), lineWithEnding.size(), stdout);
                    (void) std::fflush(stdout);
                }
            }

            lineStart = lineEnd;
        }
    }

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

    // Serialises the LinkImage (or archives the objects) and writes the artifact, returning false with
    // job.error filled on any failure. Split out so executeInternalLink records job.ok in one place.
    bool runInternalLink(LinkJob& job, ImageWriter& writer)
    {
        std::vector<std::byte> bytes;
        std::vector<std::byte> pdbBytes;
        switch (job.output)
        {
            case LinkJob::Output::Executable:
            case LinkJob::Output::SharedLibrary:
                if (!writer.writeImage(bytes, pdbBytes, job.error, job.image, job.debugInfo, job.pdbPath))
                    return false;
                break;
            case LinkJob::Output::StaticLibrary:
                if (!writer.buildStaticArchive(bytes, job.error, job.archiveMembers))
                    return false;
                break;
        }

        if (!writeJobArtifact(job, job.outputPath, bytes))
            return false;

        // Debug-info sidecar (PDB), written next to the image when debug info is enabled.
        if (!pdbBytes.empty() && !writeJobArtifact(job, job.pdbPath, pdbBytes))
            return false;

        // A shared library also produces an import library next to it so dependents can link by name.
        if (job.output == LinkJob::Output::SharedLibrary)
        {
            std::vector<Utf8> exportNames;
            exportNames.reserve(job.image.exports.size());
            for (const LinkExport& exported : job.image.exports)
                exportNames.push_back(exported.name);

            std::vector<std::byte> libBytes;
            writer.buildImportLibrary(libBytes, Utf8(job.outputPath.filename()).view(), exportNames);

            const fs::path libPath = fs::path(job.outputPath).replace_extension(".lib");
            if (!writeJobArtifact(job, libPath, libBytes))
                return false;
        }

        return true;
    }

    // Internal mode: serialise the LinkImage (or archive the objects) and write the artifact. Runs on a
    // background thread and so touches nothing but the self-contained job. The target format is chosen
    // from the job alone (set during prepareLink), so this stays usable on a detached thread.
    void executeInternalLink(LinkJob& job)
    {
        const std::unique_ptr<ImageWriter> writer = ImageWriter::create(job.targetOs);
        SWC_ASSERT(writer != nullptr);
        job.ok = runInternalLink(job, *writer);
    }

    // External mode: spawn the platform toolchain and wait. The system error is captured immediately so
    // finishLink can report it accurately even when it runs later on another thread.
    void executeExternalLink(LinkJob& job)
    {
        Os::ProcessRunOptions runOptions;
        runOptions.capturedOutput = &job.capturedOutput;
        runOptions.forwardOutput  = false;
        runOptions.logCtx         = nullptr;

        job.runResult   = Os::runProcess(job.exitCode, job.exePath, job.runArgs, job.buildDir, &runOptions);
        job.systemError = Os::systemError();
        job.ok          = job.runResult == Os::ProcessRunResult::Ok && job.exitCode == 0;
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
            if (builder.ctx().cmdLine().externalLink)
                return std::make_unique<CoffLinker>(builder);
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

Result Linker::prepareToolRun(LinkJob& outJob, const fs::path& exePath, const std::vector<Utf8>& args, const Os::ProcessRunOptions* options) const
{
    SWC_ASSERT(builder_ != nullptr);
    outJob.mode             = LinkJob::Mode::External;
    outJob.exePath          = exePath;
    outJob.buildDir         = builder_->buildDir;
    outJob.outputLineFilter = options ? options->outputLineFilter : std::function<bool(std::string_view)>{};

    if (shouldUseResponseFile(exePath, args))
    {
        const fs::path rspPath = responseFilePath(*builder_, exePath);
        SWC_RESULT(writeResponseFile(*builder_, rspPath, args));
        outJob.runArgs.clear();
        outJob.runArgs.emplace_back(std::format("@{}", Utf8(rspPath.filename())));
        return Result::Continue;
    }

    outJob.runArgs = args;
    return Result::Continue;
}

void Linker::executeLink(LinkJob& job)
{
    job.executed = true;
    if (job.mode == LinkJob::Mode::Internal)
        executeInternalLink(job);
    else
        executeExternalLink(job);
}

Result Linker::finishLink(const LinkJob& job) const
{
    SWC_ASSERT(builder_ != nullptr);
    SWC_ASSERT(job.executed);

    if (job.mode == LinkJob::Mode::Internal)
    {
        if (!job.ok)
            return builder_->reportError(job.error);
        if (!fs::exists(builder_->artifactPath))
            return builder_->reportError(DiagnosticId::cmd_err_native_artifact_missing, Diagnostic::ARG_PATH, Utf8(builder_->artifactPath));
        SWC_RESULT(builder_->publishExecutableDependencies());
        return Result::Continue;
    }

    switch (job.runResult)
    {
        case Os::ProcessRunResult::Ok:
            break;
        case Os::ProcessRunResult::StartFailed:
            return builder_->reportError(DiagnosticId::cmd_err_native_tool_start_failed, Diagnostic::ARG_PATH, Utf8(job.exePath), Diagnostic::ARG_BECAUSE, job.systemError);
        case Os::ProcessRunResult::WaitFailed:
            return builder_->reportError(DiagnosticId::cmd_err_native_tool_wait_failed, Diagnostic::ARG_PATH, Utf8(job.exePath));
        case Os::ProcessRunResult::ExitCodeFailed:
            return builder_->reportError(DiagnosticId::cmd_err_native_tool_exit_code_failed, Diagnostic::ARG_PATH, Utf8(job.exePath), Diagnostic::ARG_BECAUSE, job.systemError);
    }

    if (job.exitCode != 0)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_native_tool_failed);
        diag.addArgument(Diagnostic::ARG_TOOL, Utf8(job.exePath.filename()));
        diag.addArgument(Diagnostic::ARG_VALUE, Os::formatProcessExitCode(job.exitCode));
        if (!job.capturedOutput.empty())
        {
            std::string_view trimmedOutput = job.capturedOutput;
            while (!trimmedOutput.empty() && (trimmedOutput.back() == '\n' || trimmedOutput.back() == '\r'))
                trimmedOutput.remove_suffix(1);
            diag.addArgument(Diagnostic::ARG_BECAUSE, Utf8{trimmedOutput});
            diag.addNote(DiagnosticId::cmd_note_native_tool_output);
        }

        diag.report(builder_->ctx());
        return Result::Error;
    }

    replayToolOutput(&builder_->ctx(), job.capturedOutput, job.outputLineFilter);
    if (!fs::exists(builder_->artifactPath))
        return builder_->reportError(DiagnosticId::cmd_err_native_artifact_missing, Diagnostic::ARG_PATH, Utf8(builder_->artifactPath));
    if (builder_->compiler().buildCfg().backend.debugInfo &&
        builder_->compiler().buildCfg().backendKind != Runtime::BuildCfgBackendKind::StaticLibrary &&
        !fs::exists(builder_->pdbPath))
    {
        return builder_->reportError(DiagnosticId::cmd_err_native_artifact_missing, Diagnostic::ARG_PATH, Utf8(builder_->pdbPath));
    }

    SWC_RESULT(builder_->publishExecutableDependencies());
    return Result::Continue;
}

SWC_END_NAMESPACE();
