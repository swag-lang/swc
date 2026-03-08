#include "pch.h"
#include "Backend/Native/NativeBackend_Priv.h"

SWC_BEGIN_NAMESPACE();

namespace NativeBackendDetail
{
    bool NativeBackendBuilder::discoverToolchain()
    {
        toolchain_ = {};
        if (!discoverMsvcToolchain())
            return false;
        if (!discoverWindowsSdk())
            return false;
        return true;
    }

    bool NativeBackendBuilder::discoverMsvcToolchain()
    {
        std::vector<fs::path> candidates;

        if (const auto vctools = readEnvUtf8("VCToolsInstallDir"))
            candidates.emplace_back(std::string(*vctools));

        const auto appendRoots = [&](const fs::path& basePath) {
            std::error_code ec;
            if (!fs::exists(basePath, ec))
                return;

            std::vector<fs::path> versionRoots;
            for (fs::directory_iterator it(basePath, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
            {
                if (ec)
                {
                    ec.clear();
                    continue;
                }

                if (!it->is_directory(ec))
                {
                    ec.clear();
                    continue;
                }

                for (fs::directory_iterator skuIt(it->path(), fs::directory_options::skip_permission_denied, ec), skuEnd; skuIt != skuEnd; skuIt.increment(ec))
                {
                    if (ec)
                    {
                        ec.clear();
                        continue;
                    }

                    if (!skuIt->is_directory(ec))
                    {
                        ec.clear();
                        continue;
                    }

                    const fs::path toolsDir = skuIt->path() / "VC" / "Tools" / "MSVC";
                    if (!fs::exists(toolsDir, ec))
                        continue;

                    for (fs::directory_iterator toolIt(toolsDir, fs::directory_options::skip_permission_denied, ec), toolEnd; toolIt != toolEnd; toolIt.increment(ec))
                    {
                        if (ec)
                        {
                            ec.clear();
                            continue;
                        }

                        if (toolIt->is_directory(ec))
                            versionRoots.push_back(toolIt->path());
                    }
                }
            }

            std::ranges::sort(versionRoots, std::greater<>{}, [](const fs::path& path) {
                return path.filename().generic_string();
            });
            for (const auto& one : versionRoots)
                candidates.push_back(one);
        };

        appendRoots("C:\\Program Files\\Microsoft Visual Studio");
        appendRoots("C:\\Program Files (x86)\\Microsoft Visual Studio");

        for (const auto& root : candidates)
        {
            std::error_code ec;
            const fs::path  linkExe = root / "bin" / "Hostx64" / "x64" / "link.exe";
            const fs::path  libExe  = root / "bin" / "Hostx64" / "x64" / "lib.exe";
            const fs::path  vcLib   = root / "lib" / "x64";
            if (!fs::exists(linkExe, ec) || !fs::exists(libExe, ec))
                continue;

            toolchain_.linkExe   = linkExe;
            toolchain_.libExe    = libExe;
            toolchain_.vcLibPath = vcLib;
            return true;
        }

        return reportError("cannot find link.exe/lib.exe for the Windows native backend");
    }

    bool NativeBackendBuilder::discoverWindowsSdk()
    {
        std::vector<fs::path> candidates;

        if (const auto sdkDir = readEnvUtf8("WindowsSdkDir"))
        {
            const fs::path libRoot = fs::path(std::string(*sdkDir)) / "Lib";
            if (const auto sdkVersion = readEnvUtf8("WindowsSDKVersion"))
                candidates.emplace_back(libRoot / std::string(*sdkVersion));
        }

        std::error_code ec;
        const fs::path  sdkRoot = R"(C:\Program Files (x86)\Windows Kits\10\Lib)";
        if (fs::exists(sdkRoot, ec))
        {
            std::vector<fs::path> versions;
            for (fs::directory_iterator it(sdkRoot, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
            {
                if (ec)
                {
                    ec.clear();
                    continue;
                }

                if (it->is_directory(ec))
                    versions.push_back(it->path());
            }

            std::ranges::sort(versions, std::greater<>{}, [](const fs::path& path) {
                return path.filename().generic_string();
            });
            for (const auto& version : versions)
                candidates.push_back(version);
        }

        for (const auto& root : candidates)
        {
            const fs::path umLib   = root / "um" / "x64";
            const fs::path ucrtLib = root / "ucrt" / "x64";
            if (!fs::exists(umLib, ec) || !fs::exists(ucrtLib, ec))
                continue;

            toolchain_.sdkUmLibPath   = umLib;
            toolchain_.sdkUcrtLibPath = ucrtLib;
            return true;
        }

        return reportError("cannot find Windows SDK libraries for the native backend");
    }

    bool NativeBackendBuilder::linkArtifact() const
    {
        std::vector<Utf8> args;
        const fs::path*   exePath = nullptr;
        switch (compiler_.buildCfg().backendKind)
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
                return reportError("invalid native backend kind");
        }

        uint32_t exitCode = 0;
        if (!runProcess(*exePath, args, workDir_, exitCode))
            return false;
        if (exitCode != 0)
            return reportError(std::format("{} exited with code {}", makeUtf8(exePath->filename()), exitCode));
        if (!fs::exists(artifactPath_))
            return reportError(std::format("native backend did not produce [{}]", makeUtf8(artifactPath_)));
        return true;
    }

    std::vector<Utf8> NativeBackendBuilder::buildLinkArguments(const bool dll) const
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

        args.emplace_back(std::format("/OUT:{}", makeUtf8(artifactPath_)));
        appendLinkSearchPaths(args);

        for (const auto& object : objectDescriptions_)
            args.push_back(makeUtf8(object.objPath));

        std::set<Utf8> libraries;
        collectLinkLibraries(libraries);
        for (const Utf8& library : libraries)
            args.push_back(library);

        if (dll)
        {
            for (const auto& info : functionInfos_)
            {
                if (info.exported)
                    args.emplace_back(std::format("/EXPORT:{}", info.symbolName));
            }
        }

        appendUserLinkerArgs(args);
        return args;
    }

    std::vector<Utf8> NativeBackendBuilder::buildLibArguments() const
    {
        std::vector<Utf8> args;
        args.emplace_back("/NOLOGO");
        args.emplace_back("/MACHINE:X64");
        args.emplace_back(std::format("/OUT:{}", makeUtf8(artifactPath_)));
        for (const auto& object : objectDescriptions_)
            args.push_back(makeUtf8(object.objPath));
        return args;
    }

    void NativeBackendBuilder::appendLinkSearchPaths(std::vector<Utf8>& args) const
    {
        if (!toolchain_.vcLibPath.empty())
            args.emplace_back(std::format("/LIBPATH:{}", makeUtf8(toolchain_.vcLibPath)));
        if (!toolchain_.sdkUmLibPath.empty())
            args.emplace_back(std::format("/LIBPATH:{}", makeUtf8(toolchain_.sdkUmLibPath)));
        if (!toolchain_.sdkUcrtLibPath.empty())
            args.emplace_back(std::format("/LIBPATH:{}", makeUtf8(toolchain_.sdkUcrtLibPath)));
    }

    void NativeBackendBuilder::collectLinkLibraries(std::set<Utf8>& out) const
    {
        for (const Utf8& library : compiler_.foreignLibs())
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

        for (const auto& info : functionInfos_)
            collectFromCode(*info.machineCode);
        if (startup_)
            collectFromCode(startup_->code);
    }

    Utf8 NativeBackendBuilder::normalizeLibraryName(const std::string_view value)
    {
        Utf8 out(value);
        if (fs::path(std::string(out)).extension().empty())
            out += ".lib";
        out.make_lower();
        return out;
    }

    void NativeBackendBuilder::appendUserLinkerArgs(std::vector<Utf8>& args) const
    {
        const Runtime::String& linkerArgs = compiler_.buildCfg().linkerArgs;
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

    bool NativeBackendBuilder::runGeneratedArtifact() const
    {
        uint32_t exitCode = 0;
        if (!runProcess(artifactPath_, {}, workDir_, exitCode))
            return false;
        if (exitCode != 0)
            return reportError(std::format("generated executable exited with code {}", exitCode));
        return true;
    }

    bool NativeBackendBuilder::runProcess(const fs::path&          exePath,
                                          const std::vector<Utf8>& args,
                                          const fs::path&          workingDirectory,
                                          uint32_t&                outExitCode) const
    {
        std::wstring commandLine;
        appendQuotedCommandArg(commandLine, exePath.wstring());
        for (const Utf8& arg : args)
        {
            commandLine.push_back(L' ');
            appendQuotedCommandArg(commandLine, toWide(arg));
        }

        STARTUPINFOW        startupInfo{};
        PROCESS_INFORMATION processInfo{};
        startupInfo.cb = sizeof(startupInfo);

        std::wstring       mutableCommandLine = commandLine;
        const std::wstring workingDirW        = workingDirectory.empty() ? std::wstring() : workingDirectory.wstring();
        if (!CreateProcessW(exePath.wstring().c_str(),
                            mutableCommandLine.data(),
                            nullptr,
                            nullptr,
                            FALSE,
                            0,
                            nullptr,
                            workingDirW.empty() ? nullptr : workingDirW.c_str(),
                            &startupInfo,
                            &processInfo))
        {
            return reportError(std::format("cannot start [{}]: {}", makeUtf8(exePath), Os::systemError()));
        }

        const DWORD waitResult = WaitForSingleObject(processInfo.hProcess, INFINITE);
        if (waitResult != WAIT_OBJECT_0)
        {
            CloseHandle(processInfo.hThread);
            CloseHandle(processInfo.hProcess);
            return reportError(std::format("waiting for [{}] failed", makeUtf8(exePath)));
        }

        DWORD exitCode = 0;
        if (!GetExitCodeProcess(processInfo.hProcess, &exitCode))
        {
            CloseHandle(processInfo.hThread);
            CloseHandle(processInfo.hProcess);
            return reportError(std::format("cannot get exit code for [{}]: {}", makeUtf8(exePath), Os::systemError()));
        }

        CloseHandle(processInfo.hThread);
        CloseHandle(processInfo.hProcess);
        outExitCode = exitCode;
        return true;
    }
}

SWC_END_NAMESPACE();
