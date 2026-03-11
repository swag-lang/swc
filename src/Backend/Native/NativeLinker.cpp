#include "pch.h"
#include "Backend/Native/NativeLinker.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeLinkerCoff.h"

SWC_BEGIN_NAMESPACE();

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

Result NativeLinker::runToolAndValidateArtifacts(const fs::path& exePath, const std::vector<Utf8>& args) const
{
    uint32_t   exitCode = 0;
    const auto result   = Os::runProcess(exitCode, exePath, args, builder_.buildDir);
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
        return builder_.reportError(DiagnosticId::cmd_err_native_tool_failed, Diagnostic::ARG_TOOL, Utf8(exePath.filename()), Diagnostic::ARG_VALUE, exitCode);
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
