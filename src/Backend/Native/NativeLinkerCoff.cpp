#include "pch.h"
#include "Backend/Native/NativeLinkerCoff.h"
#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Utf8 normalizeLibraryFileName(const std::string_view value)
    {
        Utf8 out(value);
        out.make_lower();
        if (fs::path(std::string(out)).extension().empty())
            out += ".lib";
        return out;
    }
}

NativeLinkerCoff::NativeLinkerCoff(NativeBackendBuilder& builder) :
    builder_(builder)
{
}

Os::WindowsToolchainDiscoveryResult NativeLinkerCoff::queryToolchainPaths(Os::WindowsToolchainPaths& outToolchain)
{
    outToolchain = {};
    return Os::discoverWindowsToolchainPaths(outToolchain);
}

Result NativeLinkerCoff::discoverToolchain()
{
    switch (queryToolchainPaths(toolchain_))
    {
        case Os::WindowsToolchainDiscoveryResult::Ok:
            return Result::Continue;
        case Os::WindowsToolchainDiscoveryResult::MissingMsvcToolchain:
            return builder_.reportError(DiagnosticId::cmd_err_native_toolchain_msvc_missing);
        case Os::WindowsToolchainDiscoveryResult::MissingWindowsSdk:
            return builder_.reportError(DiagnosticId::cmd_err_native_toolchain_sdk_missing);
    }

    SWC_UNREACHABLE();
}

Result NativeLinkerCoff::link()
{
    SWC_RESULT_VERIFY(discoverToolchain());
    
    std::vector<Utf8> args;
    const fs::path*   exePath = nullptr;

    switch (builder_.compiler().buildCfg().backendKind)
    {
        case Runtime::BuildCfgBackendKind::Executable:
            args    = buildLinkArguments(false);
            exePath = &toolchain_.linkExe;
            break;
        case Runtime::BuildCfgBackendKind::Library:
            args    = buildLinkArguments(true);
            exePath = &toolchain_.linkExe;
            break;
        case Runtime::BuildCfgBackendKind::Export:
            args    = buildLibArguments();
            exePath = &toolchain_.libExe;
            break;
        case Runtime::BuildCfgBackendKind::None:
            SWC_UNREACHABLE();
    }

    uint32_t   exitCode = 0;
    const auto result   = Os::runProcess(exitCode, *exePath, args, builder_.buildDir);
    switch (result)
    {
        case Os::ProcessRunResult::Ok:
            break;
        case Os::ProcessRunResult::StartFailed:
            return builder_.reportError(DiagnosticId::cmd_err_native_tool_start_failed, Diagnostic::ARG_PATH, Utf8(*exePath), Diagnostic::ARG_BECAUSE, Os::systemError());
        case Os::ProcessRunResult::WaitFailed:
            return builder_.reportError(DiagnosticId::cmd_err_native_tool_wait_failed, Diagnostic::ARG_PATH, Utf8(*exePath));
        case Os::ProcessRunResult::ExitCodeFailed:
            return builder_.reportError(DiagnosticId::cmd_err_native_tool_exit_code_failed, Diagnostic::ARG_PATH, Utf8(*exePath), Diagnostic::ARG_BECAUSE, Os::systemError());
    }

    if (exitCode != 0)
        return builder_.reportError(DiagnosticId::cmd_err_native_tool_failed, Diagnostic::ARG_TOOL, Utf8(exePath->filename()), Diagnostic::ARG_VALUE, exitCode);
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

std::vector<Utf8> NativeLinkerCoff::buildLinkArguments(const bool dll) const
{
    std::vector<Utf8> args;
    args.emplace_back("/NOLOGO");
    args.emplace_back("/NODEFAULTLIB");
    args.emplace_back("/INCREMENTAL:NO");
    args.emplace_back("/MACHINE:X64");
    if (builder_.compiler().buildCfg().backend.debugInfo)
    {
        args.emplace_back("/DEBUG:FULL");
        args.emplace_back(std::format("/PDB:{}", Utf8(builder_.pdbPath)));
    }
    if (dll)
    {
        args.emplace_back("/DLL");
        args.emplace_back("/NOENTRY");
    }
    else
    {
        args.emplace_back("/SUBSYSTEM:CONSOLE");
        args.emplace_back("/ENTRY:mainCRTStartup");
    }

    args.emplace_back(std::format("/OUT:{}", Utf8(builder_.artifactPath)));
    appendLinkSearchPaths(args);

    for (const auto& object : builder_.objectDescriptions)
        args.emplace_back(object.objPath);

    std::set<Utf8> libraries;
    collectLinkLibraries(libraries);
    for (const Utf8& library : libraries)
        args.push_back(library);

    if (dll)
    {
        for (const auto& info : builder_.functionInfos)
        {
            if (info.exported)
                args.emplace_back(std::format("/EXPORT:{}", info.symbolName));
        }
    }

    appendUserLinkerArgs(args);
    return args;
}

std::vector<Utf8> NativeLinkerCoff::buildLibArguments() const
{
    std::vector<Utf8> args;
    args.emplace_back("/NOLOGO");
    args.emplace_back("/MACHINE:X64");
    args.emplace_back(std::format("/OUT:{}", Utf8(builder_.artifactPath)));
    for (const auto& object : builder_.objectDescriptions)
        args.emplace_back(object.objPath);
    return args;
}

void NativeLinkerCoff::appendLinkSearchPaths(std::vector<Utf8>& args) const
{
    if (!toolchain_.vcLibPath.empty())
        args.emplace_back(std::format("/LIBPATH:{}", Utf8(toolchain_.vcLibPath)));
    if (!toolchain_.sdkUmLibPath.empty())
        args.emplace_back(std::format("/LIBPATH:{}", Utf8(toolchain_.sdkUmLibPath)));
    if (!toolchain_.sdkUcrtLibPath.empty())
        args.emplace_back(std::format("/LIBPATH:{}", Utf8(toolchain_.sdkUcrtLibPath)));
}

void NativeLinkerCoff::collectLinkLibraries(std::set<Utf8>& out) const
{
    for (const Utf8& library : builder_.compiler().foreignLibs())
        out.emplace(normalizeLibraryFileName(library));

    const auto collectFromCode = [&](const MachineCode& code) {
        for (const auto& relocation : code.codeRelocations)
        {
            if (relocation.kind != MicroRelocation::Kind::ForeignFunctionAddress || !relocation.targetSymbol)
                continue;
            const auto* function = relocation.targetSymbol->safeCast<SymbolFunction>();
            if (!function)
                continue;
            const std::string_view libraryName = function->foreignLinkModuleName().empty() ? function->foreignModuleName() : function->foreignLinkModuleName();
            if (!libraryName.empty())
                out.emplace(normalizeLibraryFileName(libraryName));
        }
    };

    for (const auto& info : builder_.functionInfos)
        collectFromCode(*info.machineCode);
    if (builder_.startup)
        collectFromCode(builder_.startup->code);
}

void NativeLinkerCoff::appendUserLinkerArgs(std::vector<Utf8>& args) const
{
    const Runtime::String& linkerArgs = builder_.compiler().buildCfg().linkerArgs;
    if (!linkerArgs.ptr || linkerArgs.length == 0)
        return;

    const std::string_view raw(linkerArgs.ptr, linkerArgs.length);
    size_t                 index = 0;
    while (index < raw.size())
    {
        while (index < raw.size() && std::isspace(static_cast<unsigned char>(raw[index])))
            ++index;
        if (index >= raw.size())
            break;

        size_t end = index;
        while (end < raw.size() && !std::isspace(static_cast<unsigned char>(raw[end])))
            ++end;
        args.emplace_back(raw.substr(index, end - index));
        index = end;
    }
}

SWC_END_NAMESPACE();
