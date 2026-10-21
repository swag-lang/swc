#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/RuntimeName.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandPrint.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Main/WorkspaceLayout.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using CommandPrint::addInfoEntry;
    using CommandPrint::nextHelpGroupStyle;

    void addFolderEntry(std::vector<Logger::FieldEntry>& entries, const std::string_view label, const fs::path& path)
    {
        if (path.empty())
        {
            addInfoEntry(entries, label, "(not found)", LogColor::Reset);
            return;
        }

        const fs::path  absolute = FileSystem::absolutePathNoThrow(path);
        std::error_code ec;
        const bool      present = fs::is_directory(absolute, ec);
        const char*     state   = present ? " [present]" : " [absent]";
        if (ec && ec != std::errc::no_such_file_or_directory)
            state = " [cannot inspect]";
        CommandPrint::addInfoEntryParts(entries, label, {{Utf8(absolute.string()), LogColor::Reset}, {state, LogColor::Dim}});
    }

    void printInstallation(const TaskContext& ctx, const fs::path& resources, const fs::path& stdRoot, bool& hasPrintedGroup)
    {
        std::vector<Logger::FieldEntry> entries;
        addFolderEntry(entries, "Resources", resources);
        addFolderEntry(entries, "Runtime", resources / "runtime");
        addFolderEntry(entries, "Standard library", stdRoot);
        if (!stdRoot.empty())
            addFolderEntry(entries, "Standard artifacts", WorkspaceLayout::workspaceOutputDirectory(stdRoot));
        addFolderEntry(entries, "Documentation", resources / "help");
        addFolderEntry(entries, "Examples", resources / "examples");
        addFolderEntry(entries, "Applications", resources / "apps");
        addInfoEntry(entries, "Library lookup", "Use std beside the compiler first, then SWAG_PATH/std", LogColor::Reset);
        Logger::printFieldGroup(ctx, "Installation", entries, nextHelpGroupStyle(hasPrintedGroup));

        std::vector<Utf8> modules;
        std::error_code   ec;
        if (!stdRoot.empty())
        {
            for (fs::directory_iterator it(stdRoot / "modules", fs::directory_options::skip_permission_denied, ec), end; !ec && it != end; it.increment(ec))
            {
                std::error_code entryError;
                if (fs::is_regular_file(it->path() / "module.swg", entryError))
                    modules.emplace_back(it->path().filename().string());
            }
        }
        std::ranges::sort(modules);
        entries.clear();
        addInfoEntry(entries, "Source modules", modules.empty() ? Utf8("(none found)") : Utf8Helper::join(modules, ", "), LogColor::Reset);
        if (ec)
            addInfoEntry(entries, "Module scan", FileSystem::normalizeSystemMessage(ec), LogColor::Reset);
        addInfoEntry(entries, "Availability", "List source modules; generated artifacts depend on the build configuration", LogColor::Reset);
        Logger::printFieldGroup(ctx, "Standard modules", entries, nextHelpGroupStyle(hasPrintedGroup));
    }

    void printCaches(const TaskContext& ctx, bool& hasPrintedGroup)
    {
        std::vector<Logger::FieldEntry> entries;
        addFolderEntry(entries, "Cache root", WorkspaceLayout::cacheRoot());
        addFolderEntry(entries, "Dependency copies", WorkspaceLayout::dependencyCacheRoot());
        addFolderEntry(entries, "Dependency staging", WorkspaceLayout::dependencyCacheStagingRoot());
        addFolderEntry(entries, "Machine code", WorkspaceLayout::machineCacheRoot());
        addFolderEntry(entries, "Legacy scripts", WorkspaceLayout::legacyScriptCacheRoot());
        addInfoEntry(entries, "Preview cleanup", "swc clean --cache --dry-run", LogColor::Reset);
        Logger::printFieldGroup(ctx, "Caches", entries, nextHelpGroupStyle(hasPrintedGroup));
    }

    void printProjectFolders(const TaskContext& ctx, bool& hasPrintedGroup)
    {
        const CommandLine&              cmdLine = ctx.cmdLine();
        std::vector<Logger::FieldEntry> entries;
        if (!cmdLine.workspacePath.empty())
        {
            const fs::path module(cmdLine.workspaceModuleFilter.c_str());
            addFolderEntry(entries, "Workspace", cmdLine.workspacePath);
            addFolderEntry(entries, "Modules", cmdLine.workspacePath / "modules");
            addFolderEntry(entries, "Build outputs", WorkspaceLayout::workspaceOutputDirectory(cmdLine.workspacePath) / module);
            addFolderEntry(entries, "Intermediate files", WorkspaceLayout::workspaceWorkDirectory(cmdLine.workspacePath) / module);
            addFolderEntry(entries, "Dependency copies", WorkspaceLayout::workspaceDependencyDirectory(cmdLine.workspacePath));
        }
        else if (!cmdLine.modulePath.empty())
        {
            addFolderEntry(entries, "Module", cmdLine.modulePath);
            addFolderEntry(entries, "Build outputs", WorkspaceLayout::workspaceOutputDirectory(cmdLine.modulePath));
            addFolderEntry(entries, "Intermediate files", WorkspaceLayout::workspaceWorkDirectory(cmdLine.modulePath));
        }
        else
            addInfoEntry(entries, "Project folders", "Use swc info --workspace <path> or swc info --module <path>", LogColor::Reset);
        Logger::printFieldGroup(ctx, "Project", entries, nextHelpGroupStyle(hasPrintedGroup));
    }

    void printNativeToolchain(const TaskContext& ctx, bool& hasPrintedGroup)
    {
        Os::WindowsToolchainPaths       toolchain;
        const auto                      result = Os::discoverWindowsToolchainPaths(toolchain);
        std::vector<Logger::FieldEntry> entries;
        const bool                      ready = result == Os::WindowsToolchainDiscoveryResult::Ok;
        addInfoEntry(entries, "Native build", ready ? "ready" : "missing build tools", ready ? LogColor::BrightGreen : LogColor::BrightRed);
        addInfoEntry(entries, "Linker", "Integrated in swc", LogColor::Reset);
        addFolderEntry(entries, "MSVC x64 libraries", toolchain.vcLibPath);
        addFolderEntry(entries, "Windows SDK UM", toolchain.sdkUmLibPath);
        addFolderEntry(entries, "Windows SDK UCRT", toolchain.sdkUcrtLibPath);
        if (toolchain.vcLibPath.empty())
            addInfoEntry(entries, "MSVC setup", "Install the MSVC x64 build tools from Visual Studio Build Tools", LogColor::Reset);
        if (toolchain.sdkUmLibPath.empty())
            addInfoEntry(entries, "SDK setup", "Install the Windows SDK with UM and UCRT x64 libraries", LogColor::Reset);
        Logger::printFieldGroup(ctx, "Native toolchain", entries, nextHelpGroupStyle(hasPrintedGroup));
    }
}

void Command::info(const TaskContext& ctx)
{
    const Logger::ScopedLock loggerLock(ctx.global().logger());
    const fs::path           executable      = Os::getExeFullName();
    const fs::path           resources       = FileSystem::compilerResourceRoot(executable);
    const fs::path           stdRoot         = FileSystem::standardLibraryWorkspaceRoot(executable);
    bool                     hasPrintedGroup = true;

    CommandPrint::printCompilerHeader(ctx);
    std::vector<Logger::FieldEntry> entries;
    addInfoEntry(entries, "Executable", executable, LogColor::Reset);
#if SWC_DEV_MODE
    addInfoEntry(entries, "Compiler build", "devmode", LogColor::Reset);
#else
    addInfoEntry(entries, "Compiler build", "release", LogColor::Reset);
#endif
    addInfoEntry(entries, "Host OS", Os::hostOsName(), LogColor::Reset);
    addInfoEntry(entries, "Host CPU", Os::hostCpuName(), LogColor::Reset);
    addInfoEntry(entries, "Native target", std::format("{} / {}", targetOsName(ctx.cmdLine().targetOs), targetArchName(ctx.cmdLine().targetArch)), LogColor::Reset);
    addInfoEntry(entries, "Build configurations", Utf8(ctx.cmdLine().defaultBuildCfg.registeredConfigs), LogColor::Reset);
    addInfoEntry(entries, "Source files", ".swg (module source), .swgs (runnable script)", LogColor::Reset);
    Logger::printFieldGroup(ctx, "Compiler", entries, nextHelpGroupStyle(hasPrintedGroup));

    printInstallation(ctx, resources, stdRoot, hasPrintedGroup);
    printCaches(ctx, hasPrintedGroup);
    printProjectFolders(ctx, hasPrintedGroup);
    printNativeToolchain(ctx, hasPrintedGroup);

    entries.clear();
    addFolderEntry(entries, "Current directory", FileSystem::currentPathNoThrow());
    addFolderEntry(entries, "Temporary directory", Os::getTemporaryPath());
    for (const char* name : {"SWAG_PATH", "VCToolsInstallDir", "WindowsSdkDir", "WindowsSDKVersion", "TEMP", "TMP"})
    {
        const std::optional<Utf8> value = Os::readEnvironmentVariable(name);
        addInfoEntry(entries, name, value && !value->empty() ? *value : Utf8("(not set)"), LogColor::Reset);
    }
    Logger::printFieldGroup(ctx, "Environment", entries, nextHelpGroupStyle(hasPrintedGroup));
}

SWC_END_NAMESPACE();
