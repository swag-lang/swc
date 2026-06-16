#include "pch.h"
#include "Backend/Linker/CoffLinker.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/SourceFile.h"
#include "Main/FileSystem.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t DEFAULT_EXECUTABLE_STACK_RESERVE = 8u * 1024u * 1024u;

    bool hasUserStackReserveArg(const Runtime::String& linkerArgs)
    {
        if (!linkerArgs.ptr || linkerArgs.length == 0)
            return false;

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

            const std::string_view arg = raw.substr(index, end - index);
            if (arg.size() >= 6 &&
                (arg.starts_with("/STACK") || arg.starts_with("-STACK") || arg.starts_with("/stack") || arg.starts_with("-stack")))
                return true;

            index = end;
        }

        return false;
    }

    bool shouldForwardSharedLibraryLinkerOutputLine(const std::string_view line)
    {
        return CoffLinker::shouldForwardLinkerOutputLine(line, true);
    }
}

CoffLinker::CoffLinker(NativeBackendBuilder& builder) :
    Linker(builder)
{
}

Os::WindowsToolchainDiscoveryResult CoffLinker::queryToolchainPaths(Os::WindowsToolchainPaths& outToolchain)
{
    outToolchain = {};
    return Os::discoverWindowsToolchainPaths(outToolchain);
}

Result CoffLinker::discoverToolchain()
{
    SWC_ASSERT(builder_ != nullptr);
    switch (queryToolchainPaths(toolchain_))
    {
        case Os::WindowsToolchainDiscoveryResult::Ok:
            return Result::Continue;
        case Os::WindowsToolchainDiscoveryResult::MissingMsvcToolchain:
            return builder_->reportError(DiagnosticId::cmd_err_native_toolchain_msvc_missing);
        case Os::WindowsToolchainDiscoveryResult::MissingWindowsSdk:
            return builder_->reportError(DiagnosticId::cmd_err_native_toolchain_sdk_missing);
    }

    SWC_UNREACHABLE();
}

// The integrated pipeline keeps the COFF objects in memory (objectDescriptions[].objBytes); the
// external toolchain needs them on disk. The bytes already carry the CodeView debug sections, so
// link.exe /DEBUG:FULL produces a real PDB from them.
Result CoffLinker::writeObjectFiles() const
{
    SWC_ASSERT(builder_ != nullptr);
    for (const auto& object : builder_->objectDescriptions)
    {
        FileSystem::IoErrorInfo ioError;
        if (FileSystem::writeBinaryFile(object.objPath, object.objBytes.data(), object.objBytes.size(), ioError) == Result::Continue)
            continue;

        if (ioError.problem == FileSystem::IoProblem::OpenWrite)
            return builder_->reportError(DiagnosticId::cmd_err_native_obj_open_failed, Diagnostic::ARG_PATH, Utf8(object.objPath));
        return builder_->reportError(DiagnosticId::cmd_err_native_obj_write_failed, Diagnostic::ARG_PATH, Utf8(object.objPath));
    }

    return Result::Continue;
}

Result CoffLinker::prepareLink(LinkJob& outJob)
{
    SWC_ASSERT(builder_ != nullptr);
    SWC_RESULT(discoverToolchain());
    SWC_RESULT(writeObjectFiles());

    // link.exe opens the target PDB before rewriting it (even with /DEBUG:FULL /INCREMENTAL:NO). A file
    // left by the integrated linker is in swc's own PDB format, which mspdbcore cannot parse and crashes
    // on. Remove any stale PDB so link.exe always starts from a clean one (the two backends share the
    // same output path, so switching between them must not inherit the other's PDB).
    if (builder_->compiler().buildCfg().backend.debugInfo && !builder_->pdbPath.empty())
    {
        std::error_code ec;
        fs::remove(builder_->pdbPath, ec);
    }

    std::vector<Utf8>            args;
    const fs::path*              exePath = nullptr;
    Os::ProcessRunOptions        options;
    const Os::ProcessRunOptions* runOptions = nullptr;

    switch (builder_->compiler().buildCfg().backendKind)
    {
        case Runtime::BuildCfgBackendKind::Executable:
            args    = buildLinkArguments(false);
            exePath = &toolchain_.linkExe;
            break;
        case Runtime::BuildCfgBackendKind::SharedLibrary:
            args                     = buildLinkArguments(true);
            exePath                  = &toolchain_.linkExe;
            options.outputLineFilter = shouldForwardSharedLibraryLinkerOutputLine;
            runOptions               = &options;
            break;
        case Runtime::BuildCfgBackendKind::StaticLibrary:
            args    = buildLibArguments();
            exePath = &toolchain_.libExe;
            break;
        case Runtime::BuildCfgBackendKind::Export:
        case Runtime::BuildCfgBackendKind::None:
            SWC_UNREACHABLE();
    }

    return prepareToolRun(outJob, *exePath, args, runOptions);
}

bool CoffLinker::shouldForwardLinkerOutputLine(const std::string_view line, const bool dll)
{
    if (!dll)
        return true;

    size_t index = 0;
    while (index < line.size() && std::isspace(static_cast<unsigned char>(line[index])))
        ++index;

    const std::string_view trimmed = line.substr(index);
    if (!trimmed.starts_with("Creating library "))
        return true;
    return trimmed.find(" and object ") == std::string_view::npos;
}

std::vector<Utf8> CoffLinker::buildLinkArguments(const bool dll) const
{
    SWC_ASSERT(builder_ != nullptr);
    std::vector<Utf8> args;
    args.emplace_back("/NOLOGO");
    args.emplace_back("/NODEFAULTLIB");
    args.emplace_back("/INCREMENTAL:NO");
    args.emplace_back("/MACHINE:X64");
    if (builder_->compiler().buildCfg().backend.debugInfo)
    {
        args.emplace_back("/DEBUG:FULL");
        args.emplace_back(std::format("/PDB:{}", Utf8(builder_->pdbPath)));
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
        if (!hasUserStackReserveArg(builder_->compiler().buildCfg().linkerArgs))
            args.emplace_back(std::format("/STACK:{}", DEFAULT_EXECUTABLE_STACK_RESERVE));
    }

    args.emplace_back(std::format("/OUT:{}", Utf8(builder_->artifactPath)));
    appendLinkSearchPaths(args);

    for (const auto& object : builder_->objectDescriptions)
        args.emplace_back(object.objPath);

    std::set<Utf8> libraries;
    collectLinkLibraries(libraries);
    for (const Utf8& library : libraries)
        args.push_back(library);

    if (dll)
    {
        for (const auto& info : builder_->functionInfos)
        {
            if (info.exported)
                args.emplace_back(std::format("/EXPORT:{}", info.symbolName));
        }
    }

    appendUserLinkerArgs(args);
    return args;
}

std::vector<Utf8> CoffLinker::buildLibArguments() const
{
    SWC_ASSERT(builder_ != nullptr);
    std::vector<Utf8> args;
    args.emplace_back("/NOLOGO");
    args.emplace_back("/MACHINE:X64");
    args.emplace_back(std::format("/OUT:{}", Utf8(builder_->artifactPath)));
    for (const auto& object : builder_->objectDescriptions)
        args.emplace_back(object.objPath);
    return args;
}

void CoffLinker::appendLinkSearchPaths(std::vector<Utf8>& args) const
{
    if (!toolchain_.vcLibPath.empty())
        args.emplace_back(std::format("/LIBPATH:{}", Utf8(toolchain_.vcLibPath)));
    if (!toolchain_.sdkUmLibPath.empty())
        args.emplace_back(std::format("/LIBPATH:{}", Utf8(toolchain_.sdkUmLibPath)));
    if (!toolchain_.sdkUcrtLibPath.empty())
        args.emplace_back(std::format("/LIBPATH:{}", Utf8(toolchain_.sdkUcrtLibPath)));

    std::vector<fs::path> importedLinkDirs;
    for (const fs::path& importedLinkDir : builder_->compiler().importedDependencyLinkDirs())
        importedLinkDirs.push_back(importedLinkDir);

    for (const SourceFile* file : builder_->compiler().files())
    {
        if (!file || !file->hasFlag(FileFlagsE::ImportedApi))
            continue;
        if (!file->path().has_parent_path())
            continue;

        const fs::path parentPath = file->path().parent_path().lexically_normal();
        if (std::ranges::find(importedLinkDirs, parentPath) != importedLinkDirs.end())
            continue;
        importedLinkDirs.push_back(parentPath);
    }

    for (const fs::path& importedLinkDir : importedLinkDirs)
        args.emplace_back(std::format("/LIBPATH:{}", Utf8(importedLinkDir)));
}

void CoffLinker::collectLinkLibraries(std::set<Utf8>& out) const
{
    SWC_ASSERT(builder_ != nullptr);
    for (const Utf8& library : builder_->compiler().foreignLibs())
    {
        Utf8 normalizedLibrary(library);
        normalizedLibrary.make_lower();
        if (fs::path(std::string(normalizedLibrary)).extension().empty())
            normalizedLibrary += ".lib";
        out.emplace(std::move(normalizedLibrary));
    }

    for (const auto& info : builder_->functionInfos)
    {
        for (const auto& relocation : info.machineCode->codeRelocations)
        {
            if (relocation.kind != MicroRelocation::Kind::ForeignFunctionAddress || !relocation.targetSymbol)
                continue;

            const auto* function = relocation.targetSymbol->safeCast<SymbolFunction>();
            if (!function)
                continue;

            const std::string_view libraryName = function->foreignLinkModuleName().empty() ? function->foreignModuleName() : function->foreignLinkModuleName();
            if (libraryName.empty())
                continue;

            Utf8 normalizedLibrary(libraryName);
            normalizedLibrary.make_lower();
            if (fs::path(std::string(normalizedLibrary)).extension().empty())
                normalizedLibrary += ".lib";
            out.emplace(std::move(normalizedLibrary));
        }
    }

    if (builder_->startup)
    {
        for (const auto& relocation : builder_->startup->code.codeRelocations)
        {
            if (relocation.kind != MicroRelocation::Kind::ForeignFunctionAddress || !relocation.targetSymbol)
                continue;

            const auto* function = relocation.targetSymbol->safeCast<SymbolFunction>();
            if (!function)
                continue;

            const std::string_view libraryName = function->foreignLinkModuleName().empty() ? function->foreignModuleName() : function->foreignLinkModuleName();
            if (libraryName.empty())
                continue;

            Utf8 normalizedLibrary(libraryName);
            normalizedLibrary.make_lower();
            if (fs::path(std::string(normalizedLibrary)).extension().empty())
                normalizedLibrary += ".lib";
            out.emplace(std::move(normalizedLibrary));
        }
    }
}

void CoffLinker::appendUserLinkerArgs(std::vector<Utf8>& args) const
{
    SWC_ASSERT(builder_ != nullptr);
    const Runtime::String& linkerArgs = builder_->compiler().buildCfg().linkerArgs;
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
