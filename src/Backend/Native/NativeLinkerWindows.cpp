#include "pch.h"
#include "Backend/Native/NativeLinkerWindows.h"
#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

NativeLinkerWindows::NativeLinkerWindows(NativeBackendBuilder& builder) :
    builder_(builder)
{
}

bool NativeLinkerWindows::link()
{
    if (!discoverToolchain())
        return false;
    return linkArtifact();
}

bool NativeLinkerWindows::discoverToolchain()
{
    toolchain_ = {};

    switch (Os::discoverWindowsToolchainPaths(toolchain_))
    {
        case Os::WindowsToolchainDiscoveryResult::Ok:
            return true;

        case Os::WindowsToolchainDiscoveryResult::MissingMsvcToolchain:
            return builder_.reportError("cannot find link.exe/lib.exe for the Windows native backend");

        case Os::WindowsToolchainDiscoveryResult::MissingWindowsSdk:
            return builder_.reportError("cannot find Windows SDK libraries for the native backend");
    }

    SWC_UNREACHABLE();
}

bool NativeLinkerWindows::linkArtifact()
{
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
            return builder_.reportError("invalid native backend kind");
    }

    uint32_t   exitCode = 0;
    const auto result   = Os::runProcess(exitCode, *exePath, args, builder_.state().workDir);
    switch (result)
    {
        case Os::ProcessRunResult::Ok:
            break;

        case Os::ProcessRunResult::StartFailed:
            return builder_.reportError(std::format("cannot start [{}]: {}", makeUtf8(*exePath), Os::systemError()));

        case Os::ProcessRunResult::WaitFailed:
            return builder_.reportError(std::format("waiting for [{}] failed", makeUtf8(*exePath)));

        case Os::ProcessRunResult::ExitCodeFailed:
            return builder_.reportError(std::format("cannot get exit code for [{}]: {}", makeUtf8(*exePath), Os::systemError()));
    }

    if (exitCode != 0)
        return builder_.reportError(std::format("{} exited with code {}", makeUtf8(exePath->filename()), exitCode));
    if (!fs::exists(builder_.state().artifactPath))
        return builder_.reportError(std::format("native backend did not produce [{}]", makeUtf8(builder_.state().artifactPath)));
    return true;
}

std::vector<Utf8> NativeLinkerWindows::buildLinkArguments(const bool dll) const
{
    std::vector<Utf8> args;
    args.emplace_back("/NOLOGO");
    args.emplace_back("/NODEFAULTLIB");
    args.emplace_back("/INCREMENTAL:NO");
    args.emplace_back("/MACHINE:X64");
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

    args.emplace_back(std::format("/OUT:{}", makeUtf8(builder_.state().artifactPath)));
    appendLinkSearchPaths(args);

    for (const auto& object : builder_.state().objectDescriptions)
        args.push_back(makeUtf8(object.objPath));

    std::set<Utf8> libraries;
    collectLinkLibraries(libraries);
    for (const Utf8& library : libraries)
        args.push_back(library);

    if (dll)
    {
        for (const auto& info : builder_.state().functionInfos)
        {
            if (info.exported)
                args.emplace_back(std::format("/EXPORT:{}", info.symbolName));
        }
    }

    appendUserLinkerArgs(args);
    return args;
}

std::vector<Utf8> NativeLinkerWindows::buildLibArguments() const
{
    std::vector<Utf8> args;
    args.emplace_back("/NOLOGO");
    args.emplace_back("/MACHINE:X64");
    args.emplace_back(std::format("/OUT:{}", makeUtf8(builder_.state().artifactPath)));
    for (const auto& object : builder_.state().objectDescriptions)
        args.push_back(makeUtf8(object.objPath));
    return args;
}

void NativeLinkerWindows::appendLinkSearchPaths(std::vector<Utf8>& args) const
{
    if (!toolchain_.vcLibPath.empty())
        args.emplace_back(std::format("/LIBPATH:{}", makeUtf8(toolchain_.vcLibPath)));
    if (!toolchain_.sdkUmLibPath.empty())
        args.emplace_back(std::format("/LIBPATH:{}", makeUtf8(toolchain_.sdkUmLibPath)));
    if (!toolchain_.sdkUcrtLibPath.empty())
        args.emplace_back(std::format("/LIBPATH:{}", makeUtf8(toolchain_.sdkUcrtLibPath)));
}

void NativeLinkerWindows::collectLinkLibraries(std::set<Utf8>& out) const
{
    for (const Utf8& library : builder_.compiler().foreignLibs())
        out.insert(normalizeLibraryName(library));

    const auto collectFromCode = [&](const MachineCode& code) {
        for (const auto& relocation : code.codeRelocations)
        {
            if (relocation.kind != MicroRelocation::Kind::ForeignFunctionAddress || !relocation.targetSymbol)
                continue;
            const auto* function = relocation.targetSymbol->safeCast<SymbolFunction>();
            if (!function)
                continue;
            if (!function->foreignModuleName().empty())
                out.insert(normalizeLibraryName(function->foreignModuleName()));
        }
    };

    for (const auto& info : builder_.state().functionInfos)
        collectFromCode(*info.machineCode);
    if (builder_.state().startup)
        collectFromCode(builder_.state().startup->code);
}

Utf8 NativeLinkerWindows::normalizeLibraryName(const std::string_view value)
{
    Utf8 out(value);
    if (fs::path(std::string(out)).extension().empty())
        out += ".lib";
    out.make_lower();
    return out;
}

void NativeLinkerWindows::appendUserLinkerArgs(std::vector<Utf8>& args) const
{
    const Runtime::String& linkerArgs = builder_.compiler().buildCfg().linkerArgs;
    if (!linkerArgs.ptr || linkerArgs.length == 0)
        return;

    const std::string_view raw(linkerArgs.ptr, static_cast<size_t>(linkerArgs.length));
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
