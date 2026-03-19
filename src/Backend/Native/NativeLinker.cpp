#include "pch.h"
#include "Backend/Native/NativeLinker.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeLinkerCoff.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void replayToolOutput(const std::string_view output, const std::function<bool(std::string_view)>& lineFilter)
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
                (void) std::fwrite(lineWithEnding.data(), sizeof(char), lineWithEnding.size(), stdout);
                (void) std::fflush(stdout);
            }

            lineStart = lineEnd;
        }
    }

    Utf8 trimToolOutput(std::string_view output)
    {
        while (!output.empty() && (output.back() == '\n' || output.back() == '\r'))
            output.remove_suffix(1);
        return Utf8(output);
    }
}

NativeLinker::NativeLinker(NativeBackendBuilder& builder) :
    builder_(builder)
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

Result NativeLinker::runToolAndValidateArtifacts(const fs::path& exePath, const std::vector<Utf8>& args, const Os::ProcessRunOptions* options) const
{
    uint32_t              exitCode = 0;
    std::string           toolOutput;
    Os::ProcessRunOptions runOptions;
    if (options)
        runOptions = *options;
    runOptions.capturedOutput = &toolOutput;
    runOptions.forwardOutput  = false;

    const auto result = Os::runProcess(exitCode, exePath, args, builder_.buildDir, &runOptions);
    switch (result)
    {
        case Os::ProcessRunResult::Ok:
            break;
        case Os::ProcessRunResult::StartFailed:
            return builder_.reportError(DiagnosticId::cmd_err_native_tool_start_failed, Diagnostic::ARG_PATH, Utf8(exePath), Diagnostic::ARG_BECAUSE, Os::systemError());
        case Os::ProcessRunResult::WaitFailed:
            return builder_.reportError(DiagnosticId::cmd_err_native_tool_wait_failed, Diagnostic::ARG_PATH, Utf8(exePath));
        case Os::ProcessRunResult::ExitCodeFailed:
            return builder_.reportError(DiagnosticId::cmd_err_native_tool_exit_code_failed, Diagnostic::ARG_PATH, Utf8(exePath), Diagnostic::ARG_BECAUSE, Os::systemError());
    }

    if (exitCode != 0)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_native_tool_failed);
        diag.addArgument(Diagnostic::ARG_TOOL, Utf8(exePath.filename()));
        diag.addArgument(Diagnostic::ARG_VALUE, exitCode);
        if (!toolOutput.empty())
        {
            diag.addArgument(Diagnostic::ARG_BECAUSE, trimToolOutput(toolOutput));
            diag.addNote(DiagnosticId::cmd_note_native_tool_output);
        }

        diag.report(const_cast<TaskContext&>(builder_.ctx()));
        return Result::Error;
    }

    replayToolOutput(toolOutput, runOptions.outputLineFilter);
    if (!fs::exists(builder_.artifactPath))
        return builder_.reportError(DiagnosticId::cmd_err_native_artifact_missing, Diagnostic::ARG_PATH, Utf8(builder_.artifactPath));
    if (builder_.compiler().buildCfg().backend.debugInfo &&
        builder_.compiler().buildCfg().backendKind != Runtime::BuildCfgBackendKind::Export &&
        !fs::exists(builder_.pdbPath))
    {
        return builder_.reportError(DiagnosticId::cmd_err_native_artifact_missing, Diagnostic::ARG_PATH, Utf8(builder_.pdbPath));
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
