#include "pch.h"
#include "Backend/Native/NativeLinker.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeLinkerCoff.h"
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

}

NativeLinker::NativeLinker(NativeBackendBuilder& builder) :
    builder_(&builder)
{
}

std::unique_ptr<NativeLinker> NativeLinker::create(NativeBackendBuilder& builder)
{
    switch (builder.ctx().cmdLine().targetOs)
    {
        case Runtime::TargetOs::Windows:
            return std::make_unique<NativeLinkerCoff>(builder);
    }

    SWC_UNREACHABLE();
}

Os::WindowsToolchainDiscoveryResult NativeLinker::queryToolchainPaths(const NativeBackendBuilder& builder, Os::WindowsToolchainPaths& outToolchain)
{
    switch (builder.ctx().cmdLine().targetOs)
    {
        case Runtime::TargetOs::Windows:
            return NativeLinkerCoff::queryToolchainPaths(outToolchain);
        default:
            SWC_UNREACHABLE();
    }
}

Result NativeLinker::link()
{
    NativeLinkerToolRun run;
    SWC_RESULT(prepareLink(run));
    executeToolRun(run);
    return finishToolRun(run);
}

Result NativeLinker::prepareToolRun(NativeLinkerToolRun& outRun, const fs::path& exePath, const std::vector<Utf8>& args, const Os::ProcessRunOptions* options) const
{
    SWC_ASSERT(builder_ != nullptr);
    outRun.exePath          = exePath;
    outRun.buildDir         = builder_->buildDir;
    outRun.outputLineFilter = options ? options->outputLineFilter : std::function<bool(std::string_view)>{};

    if (shouldUseResponseFile(exePath, args))
    {
        const fs::path rspPath = responseFilePath(*builder_, exePath);
        SWC_RESULT(writeResponseFile(*builder_, rspPath, args));
        outRun.runArgs.clear();
        outRun.runArgs.emplace_back(std::format("@{}", Utf8(rspPath.filename())));
        return Result::Continue;
    }

    outRun.runArgs = args;
    return Result::Continue;
}

void NativeLinker::executeToolRun(NativeLinkerToolRun& run)
{
    // Runs on whatever thread the caller chooses (foreground for a one-shot link, a background
    // thread for the workspace pipeline). Touches only the self-contained run description: no
    // compiler, builder, logger or diagnostic state is referenced here, so it is safe to overlap
    // with other module compilation. The system error is captured immediately on this thread so
    // finishToolRun can report it accurately even when it runs much later on another thread.
    Os::ProcessRunOptions runOptions;
    runOptions.capturedOutput = &run.capturedOutput;
    runOptions.forwardOutput  = false;
    runOptions.logCtx         = nullptr;

    run.runResult   = Os::runProcess(run.exitCode, run.exePath, run.runArgs, run.buildDir, &runOptions);
    run.systemError = Os::systemError();
    run.executed    = true;
}

Result NativeLinker::finishToolRun(const NativeLinkerToolRun& run) const
{
    SWC_ASSERT(builder_ != nullptr);
    SWC_ASSERT(run.executed);

    switch (run.runResult)
    {
        case Os::ProcessRunResult::Ok:
            break;
        case Os::ProcessRunResult::StartFailed:
            return builder_->reportError(DiagnosticId::cmd_err_native_tool_start_failed, Diagnostic::ARG_PATH, Utf8(run.exePath), Diagnostic::ARG_BECAUSE, run.systemError);
        case Os::ProcessRunResult::WaitFailed:
            return builder_->reportError(DiagnosticId::cmd_err_native_tool_wait_failed, Diagnostic::ARG_PATH, Utf8(run.exePath));
        case Os::ProcessRunResult::ExitCodeFailed:
            return builder_->reportError(DiagnosticId::cmd_err_native_tool_exit_code_failed, Diagnostic::ARG_PATH, Utf8(run.exePath), Diagnostic::ARG_BECAUSE, run.systemError);
    }

    if (run.exitCode != 0)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_native_tool_failed);
        diag.addArgument(Diagnostic::ARG_TOOL, Utf8(run.exePath.filename()));
        diag.addArgument(Diagnostic::ARG_VALUE, Os::formatProcessExitCode(run.exitCode));
        if (!run.capturedOutput.empty())
        {
            std::string_view trimmedOutput = run.capturedOutput;
            while (!trimmedOutput.empty() && (trimmedOutput.back() == '\n' || trimmedOutput.back() == '\r'))
                trimmedOutput.remove_suffix(1);
            diag.addArgument(Diagnostic::ARG_BECAUSE, Utf8{trimmedOutput});
            diag.addNote(DiagnosticId::cmd_note_native_tool_output);
        }

        diag.report(builder_->ctx());
        return Result::Error;
    }

    replayToolOutput(&builder_->ctx(), run.capturedOutput, run.outputLineFilter);
    if (!fs::exists(builder_->artifactPath))
        return builder_->reportError(DiagnosticId::cmd_err_native_artifact_missing, Diagnostic::ARG_PATH, Utf8(builder_->artifactPath));
    if (builder_->compiler().buildCfg().backend.debugInfo &&
        builder_->compiler().buildCfg().backendKind != Runtime::BuildCfgBackendKind::StaticLibrary &&
        !fs::exists(builder_->pdbPath))
    {
        return builder_->reportError(DiagnosticId::cmd_err_native_artifact_missing, Diagnostic::ARG_PATH, Utf8(builder_->pdbPath));
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
