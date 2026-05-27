#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Parser/Parser/ParserJob.h"
#include "Format/FormatOptionsLoader.h"
#include "Format/Formatter.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/Stats.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"
#include <thread>

#undef SWC_TEST_KIND
#define SWC_TEST_KIND swc::Unittest::TestKind::Filesystem

SWC_BEGIN_NAMESPACE();

namespace
{
    class ScopedTempTree
    {
    public:
        explicit ScopedTempTree(std::string_view name)
        {
            const fs::path tempRoot = Os::getTemporaryPath();
            SWC_ASSERT(!tempRoot.empty());

            root_ = (tempRoot / "swc_unittest" / std::format("{}_p{}", name, Os::currentProcessId())).lexically_normal();

            std::error_code ec;
            fs::remove_all(root_, ec);
            ec.clear();
            const bool created = fs::create_directories(root_, ec);
            if (!ec && (created || fs::exists(root_)))
                ready_ = true;
        }

        ~ScopedTempTree()
        {
            std::error_code ec;
            fs::remove_all(root_, ec);
        }

        bool            ready() const { return ready_; }
        const fs::path& root() const { return root_; }

    private:
        fs::path root_;
        bool     ready_ = false;
    };

    class ScopedEnvVar
    {
    public:
        ScopedEnvVar(std::string_view name, std::string_view value) :
            name_(name)
        {
            char*  currentValue = nullptr;
            size_t currentSize  = 0;
            if (_dupenv_s(&currentValue, &currentSize, name_.c_str()) == 0 && currentValue)
            {
                hadValue_      = true;
                previousValue_ = currentValue;
                std::free(currentValue);
            }

            _putenv_s(name_.c_str(), std::string(value).c_str());
        }

        ~ScopedEnvVar()
        {
            if (hadValue_)
                _putenv_s(name_.c_str(), previousValue_.c_str());
            else
                _putenv_s(name_.c_str(), "");
        }

    private:
        std::string name_;
        std::string previousValue_;
        bool        hadValue_ = false;
    };

    bool ensureDirectory(const fs::path& path)
    {
        std::error_code ec;
        if (fs::exists(path, ec))
            return !ec && fs::is_directory(path, ec);

        ec.clear();
        return fs::create_directories(path, ec) && !ec;
    }

    bool writeTextFile(const fs::path& path, std::string_view content)
    {
        const fs::path parentPath = path.parent_path();
        if (!parentPath.empty() && !ensureDirectory(parentPath))
            return false;

        std::ofstream stream(path, std::ios::binary | std::ios::trunc);
        if (!stream.is_open())
            return false;

        stream.write(content.data(), static_cast<std::streamsize>(content.size()));
        return stream.good();
    }

    bool copyDirectoryTree(const fs::path& srcPath, const fs::path& dstPath)
    {
        std::error_code ec;
        if (!fs::is_directory(srcPath, ec) || ec)
            return false;

        if (!ensureDirectory(dstPath))
            return false;

        for (fs::recursive_directory_iterator it(srcPath, ec); !ec && it != fs::recursive_directory_iterator(); ++it)
        {
            const fs::path relativePath = fs::relative(it->path(), srcPath, ec);
            if (ec)
                return false;

            const fs::path dstEntryPath = dstPath / relativePath;
            if (it->is_directory())
            {
                if (!ensureDirectory(dstEntryPath))
                    return false;

                continue;
            }

            if (!it->is_regular_file())
                continue;

            if (!ensureDirectory(dstEntryPath.parent_path()))
                return false;

            ec.clear();
            fs::copy_file(it->path(), dstEntryPath, fs::copy_options::overwrite_existing, ec);
            if (ec)
                return false;
        }

        return !ec;
    }

    void waitForTimestampTick()
    {
        std::this_thread::sleep_for(std::chrono::milliseconds(250));
    }

    bool tryGetPathWriteTime(fs::file_time_type& outTime, const fs::path& path)
    {
        std::error_code ec;
        outTime = fs::last_write_time(path, ec);
        return !ec;
    }

    bool setPathWriteTime(const fs::path& path, const fs::file_time_type time)
    {
        std::error_code ec;
        fs::last_write_time(path, time, ec);
        return !ec;
    }

    class ScopedPathWriteTime
    {
    public:
        explicit ScopedPathWriteTime(const fs::path& path) :
            path_(path)
        {
            hadTime_ = tryGetPathWriteTime(originalTime_, path_);
        }

        ~ScopedPathWriteTime()
        {
            if (hadTime_)
                setPathWriteTime(path_, originalTime_);
        }

    private:
        fs::path            path_;
        fs::file_time_type  originalTime_{};
        bool                hadTime_ = false;
    };

    bool containsPath(const std::set<fs::path>& paths, const fs::path& expectedPath)
    {
        for (const fs::path& path : paths)
        {
            if (FileSystem::pathEquals(path, expectedPath))
                return true;
        }

        return false;
    }

    const SourceFile* findCompilerFile(const CompilerInstance& compiler, const fs::path& expectedPath)
    {
        for (const SourceFile* file : compiler.files())
        {
            if (file && FileSystem::pathEquals(file->path(), expectedPath))
                return file;
        }

        return nullptr;
    }

    Result parseCommandLine(const TaskContext& ctx, CommandLine& cmdLine, const std::vector<std::string>& args)
    {
        std::vector<char*> argv;
        argv.reserve(args.size());
        for (const std::string& arg : args)
            argv.push_back(const_cast<char*>(arg.c_str()));

        CommandLineParser parser(const_cast<Global&>(ctx.global()), cmdLine);
        return parser.parse(static_cast<int>(argv.size()), argv.data());
    }

    Result formatSourceText(const Global& global, std::string_view source, const FormatOptions& options, Utf8& outText)
    {
        CommandLine cmdLine;
        cmdLine.command = CommandKind::Format;
        cmdLine.name    = "compiler_format_options_apply";

        CompilerInstance compiler(global, cmdLine);
        TaskContext      compilerCtx(compiler);

        SourceFile& sourceFile = Unittest::addTestSource(compilerCtx, "Compiler", "FormatOptionsApply", source);
        SWC_RESULT(sourceFile.loadContent(compilerCtx));

        constexpr ParserJobOptions parserOptions = {
            .emitTrivia                 = true,
            .ignoreGlobalCompilerIfSkip = true,
        };

        SWC_RESULT(parseLoadedSourceFile(compilerCtx, sourceFile, parserOptions));
        if (compilerCtx.hasError())
            return Result::Error;

        Formatter formatter(options);
        formatter.prepare(sourceFile);
        outText = formatter.text();
        return Result::Continue;
    }

    CommandLine makeSyntheticModuleFileCommand(const CommandKind command, const fs::path& moduleFilePath, const bool silent = false)
    {
        CommandLine cmdLine;
        cmdLine.command        = command;
        cmdLine.moduleFilePath = moduleFilePath;
        cmdLine.runtime        = false;
        cmdLine.silent         = silent;
        CommandLineParser::refreshBuildCfg(cmdLine);
        return cmdLine;
    }

    CommandLine makeSyntheticWorkspaceCommand(const CommandKind command, const fs::path& workspacePath, const bool silent = true)
    {
        CommandLine cmdLine;
        cmdLine.command       = command;
        cmdLine.workspacePath = workspacePath;
        cmdLine.silent        = silent;
        CommandLineParser::refreshBuildCfg(cmdLine);
        return cmdLine;
    }
}

SWC_TEST_BEGIN(Compiler_CommandLineConfigFileSetsCommandAndResolvesRelativePaths)
{
    const ScopedTempTree tempTree("compiler_config_file_sets_command");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path configDir  = tempTree.root() / "cfg";
    const fs::path sourceFile = configDir / "inputs" / "main.swg";
    const fs::path sourceDir  = configDir / "suite";
    const fs::path moduleDir  = configDir / "module";
    const fs::path configPath = configDir / "swc.cfg";

    if (!writeTextFile(sourceFile, "func main() {}\n"))
        return Result::Error;
    if (!ensureDirectory(sourceDir))
        return Result::Error;
    if (!ensureDirectory(moduleDir))
        return Result::Error;
    if (!writeTextFile(configPath, R"(# A polished config file should accept comments and quoted values.
command = test
file = ./inputs/main.swg
directory = ./suite
module = ./module
artifact-name = "cfg#artifact" # hashes inside quotes are part of the value
runtime = off
tag = "User.Name: string = hello world"
out-dir = ./out
work-dir = ./work
)"))
        return Result::Error;

    CommandLine                    cmdLine;
    const uint64_t                 errorsBefore = Stats::getNumErrors();
    const std::vector<std::string> args         = {
        "swc_devmode",
        "--config-file",
        configPath.string(),
    };

    if (parseCommandLine(ctx, cmdLine, args) != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;
    if (cmdLine.command != CommandKind::Test)
        return Result::Error;
    if (!cmdLine.commandExplicit)
        return Result::Error;
    if (!cmdLine.sourceDrivenTest)
        return Result::Error;
    if (cmdLine.runtime)
        return Result::Error;
    if (cmdLine.name != "cfg#artifact")
        return Result::Error;
    if (cmdLine.tags.size() != 1 || cmdLine.tags[0] != "User.Name: string = hello world")
        return Result::Error;
    if (!FileSystem::pathEquals(cmdLine.configFile, configPath))
        return Result::Error;
    if (!containsPath(cmdLine.files, sourceFile))
        return Result::Error;
    if (!containsPath(cmdLine.directories, sourceDir))
        return Result::Error;
    if (!FileSystem::pathEquals(cmdLine.modulePath, moduleDir))
        return Result::Error;
    if (!FileSystem::pathEquals(cmdLine.outDir, configDir / "out"))
        return Result::Error;
    if (!FileSystem::pathEquals(cmdLine.workDir, configDir / "work"))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_CommandLineConfigFileAllowsCliOverrides)
{
    const ScopedTempTree tempTree("compiler_config_file_cli_override");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path configPath = tempTree.root() / "swc.cfg";
    if (!writeTextFile(configPath, R"(command = test
runtime = off
artifact-kind = static-library
)"))
        return Result::Error;

    CommandLine                    cmdLine;
    const uint64_t                 errorsBefore = Stats::getNumErrors();
    const std::vector<std::string> args         = {
        "swc_devmode",
        "build",
        "--config-file",
        configPath.string(),
        "--runtime",
        "--artifact-kind",
        "executable",
    };

    if (parseCommandLine(ctx, cmdLine, args) != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;
    if (cmdLine.command != CommandKind::Build)
        return Result::Error;
    if (cmdLine.sourceDrivenTest)
        return Result::Error;
    if (!cmdLine.runtime)
        return Result::Error;
    if (cmdLine.backendKind != Runtime::BuildCfgBackendKind::Executable)
        return Result::Error;
    if (!cmdLine.artifactKindExplicit)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_CommandLineAcceptsInlineAssignmentSyntax)
{
    const ScopedTempTree tempTree("compiler_config_file_inline_assign");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path configPath = tempTree.root() / "swc.cfg";
    if (!writeTextFile(configPath, R"(command = test
runtime = off
)"))
        return Result::Error;

    CommandLine                    cmdLine;
    const uint64_t                 errorsBefore = Stats::getNumErrors();
    const std::vector<std::string> args         = {
        "swc_devmode",
        std::format("--config-file={}", configPath.string()),
        "--artifact-kind=static-library",
    };

    if (parseCommandLine(ctx, cmdLine, args) != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;
    if (cmdLine.command != CommandKind::Test)
        return Result::Error;
    if (!cmdLine.commandExplicit)
        return Result::Error;
    if (!cmdLine.sourceDrivenTest)
        return Result::Error;
    if (cmdLine.runtime)
        return Result::Error;
    if (cmdLine.backendKind != Runtime::BuildCfgBackendKind::StaticLibrary)
        return Result::Error;
    if (!cmdLine.artifactKindExplicit)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_CommandLineTestAcceptsImportedApiInputs)
{
    const ScopedTempTree tempTree("compiler_test_imported_api_inputs");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path importRoot = tempTree.root() / "api";
    const fs::path importDir  = importRoot / "dep" / "static-library" / "fast-debug" / "x86_64";
    const fs::path importFile = importDir / "dep.swg";

    if (!writeTextFile(importFile, "public func dependency() {}\n"))
        return Result::Error;

    CommandLine                    cmdLine;
    const uint64_t                 errorsBefore = Stats::getNumErrors();
    const std::vector<std::string> args         = {
        "swc_devmode",
        "test",
        "--import-api-dir",
        importRoot.string(),
        "--import-api-file",
        importFile.string(),
    };

    if (parseCommandLine(ctx, cmdLine, args) != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;
    if (cmdLine.command != CommandKind::Test)
        return Result::Error;
    if (!cmdLine.sourceDrivenTest)
        return Result::Error;
    if (!containsPath(cmdLine.importApiDirs, importRoot))
        return Result::Error;
    if (!containsPath(cmdLine.importApiFiles, importFile))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_CommandLineModuleFileDerivesModulePath)
{
    const ScopedTempTree tempTree("compiler_module_file_path");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path moduleDir  = tempTree.root() / "pkg";
    const fs::path moduleFile = moduleDir / "module.swg";
    if (!writeTextFile(moduleFile, "#run {}\n"))
        return Result::Error;

    CommandLine                    cmdLine;
    const uint64_t                 errorsBefore = Stats::getNumErrors();
    const std::vector<std::string> args         = {
        "swc_devmode",
        "sema",
        "--module-file",
        moduleFile.string(),
    };

    if (parseCommandLine(ctx, cmdLine, args) != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;
    if (cmdLine.command != CommandKind::Sema)
        return Result::Error;
    if (!FileSystem::pathEquals(cmdLine.moduleFilePath, moduleFile))
        return Result::Error;
    if (!FileSystem::pathEquals(cmdLine.modulePath, moduleDir))
        return Result::Error;
    if (defaultArtifactName(cmdLine) != "pkg")
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_CommandLineModuleFileResolvesRelativeInputsFromModuleFolder)
{
    const ScopedTempTree tempTree("compiler_module_file_relative_inputs");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path moduleDir  = tempTree.root() / "pkg";
    const fs::path moduleFile = moduleDir / "module.swg";
    const fs::path sourceDir  = moduleDir / "src";
    const fs::path sourceFile = sourceDir / "main.swg";
    const fs::path extraFile  = moduleDir / "extras" / "helper.swg";

    if (!writeTextFile(moduleFile, "#run {}\n"))
        return Result::Error;
    if (!writeTextFile(sourceFile, "func main() {}\n"))
        return Result::Error;
    if (!writeTextFile(extraFile, "func helper() {}\n"))
        return Result::Error;

    CommandLine                    cmdLine;
    const uint64_t                 errorsBefore = Stats::getNumErrors();
    const std::vector<std::string> args         = {
        "swc_devmode",
        "sema",
        "--module-file",
        moduleFile.string(),
        "--directory",
        "src",
        "--file",
        "extras/helper.swg",
    };

    if (parseCommandLine(ctx, cmdLine, args) != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;
    if (!containsPath(cmdLine.directories, sourceDir))
        return Result::Error;
    if (!containsPath(cmdLine.files, extraFile))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_CommandLineModuleShortFormMfResolvesModulePath)
{
    const ScopedTempTree tempTree("compiler_module_short_form_mf");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path moduleDir = tempTree.root() / "pkg";
    if (!ensureDirectory(moduleDir))
        return Result::Error;

    CommandLine                    cmdLine;
    const uint64_t                 errorsBefore = Stats::getNumErrors();
    const std::vector<std::string> args         = {
        "swc_devmode",
        "build",
        "-mf",
        moduleDir.string(),
    };

    if (parseCommandLine(ctx, cmdLine, args) != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;
    if (!FileSystem::pathEquals(cmdLine.modulePath, moduleDir))
        return Result::Error;
    if (defaultArtifactName(cmdLine) != "pkg")
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_CommandLineWorkspaceResolvesPath)
{
    const ScopedTempTree tempTree("compiler_workspace_path");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir = tempTree.root() / "workspace";
    if (!ensureDirectory(workspaceDir / "modules"))
        return Result::Error;

    CommandLine                    cmdLine;
    const uint64_t                 errorsBefore = Stats::getNumErrors();
    const std::vector<std::string> args         = {
        "swc_devmode",
        "build",
        "--workspace",
        workspaceDir.string(),
    };

    if (parseCommandLine(ctx, cmdLine, args) != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;
    if (!FileSystem::pathEquals(cmdLine.workspacePath, workspaceDir))
        return Result::Error;
    if (defaultArtifactName(cmdLine) != "workspace")
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_CommandLineWorkspaceAcceptsRebuildFlag)
{
    const ScopedTempTree tempTree("compiler_workspace_rebuild_flag");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir = tempTree.root() / "workspace";
    if (!ensureDirectory(workspaceDir / "modules"))
        return Result::Error;

    CommandLine                    cmdLine;
    const uint64_t                 errorsBefore = Stats::getNumErrors();
    const std::vector<std::string> args         = {
        "swc_devmode",
        "build",
        "--workspace",
        workspaceDir.string(),
        "--rebuild",
    };

    if (parseCommandLine(ctx, cmdLine, args) != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;
    if (!FileSystem::pathEquals(cmdLine.workspacePath, workspaceDir))
        return Result::Error;
    if (!cmdLine.rebuild)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_CommandLineWorkspaceModuleFilterResolvesPath)
{
    const ScopedTempTree tempTree("compiler_workspace_module_filter");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir = tempTree.root() / "workspace";
    if (!ensureDirectory(workspaceDir / "modules"))
        return Result::Error;

    CommandLine                    cmdLine;
    const uint64_t                 errorsBefore = Stats::getNumErrors();
    const std::vector<std::string> args         = {
        "swc_devmode",
        "build",
        "--workspace",
        workspaceDir.string(),
        "-m",
        "aoc2019",
    };

    if (parseCommandLine(ctx, cmdLine, args) != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;
    if (!FileSystem::pathEquals(cmdLine.workspacePath, workspaceDir))
        return Result::Error;
    if (cmdLine.workspaceModuleFilter != "aoc2019")
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_CommandLineWorkspaceModuleFilterRequiresWorkspace)
{
    CommandLine                    cmdLine;
    const uint64_t                 errorsBefore = Stats::getNumErrors();
    const std::vector<std::string> args         = {
        "swc_devmode",
        "build",
        "-m",
        "aoc2019",
    };

    if (parseCommandLine(ctx, cmdLine, args) != Result::Error)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore + 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceModuleDefaultsArtifactNameAndNamespaceFromModulePath)
{
    CommandLine cmdLine;
    cmdLine.command        = CommandKind::Build;
    cmdLine.workspacePath  = fs::path("workspace");
    cmdLine.modulePath     = fs::path("workspace/modules/dep");
    cmdLine.moduleFilePath = fs::path("workspace/modules/dep/module.swg");
    CommandLineParser::refreshBuildCfg(cmdLine);

    if (defaultArtifactName(cmdLine) != "dep")
        return Result::Error;
    if (Utf8(cmdLine.defaultBuildCfg.moduleNamespace) != "Dep")
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_ModuleFileSetupConfiguresBuildAndLoadsExplicitSources)
{
    const ScopedTempTree tempTree("compiler_module_file_setup");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path moduleDir   = tempTree.root() / "module";
    const fs::path moduleFile  = moduleDir / "module.swg";
    const fs::path autoSrcFile = moduleDir / "src" / "should_not_be_loaded.swg";
    const fs::path loadedFile  = tempTree.root() / "sources" / "loaded.swg";

    if (!writeTextFile(moduleFile, R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "SetupNs"
    cfg.name = "setup-artifact"
    cfg.backendKind = .StaticLibrary
}
#load("../sources/loaded.swg")
)"))
        return Result::Error;
    if (!writeTextFile(autoSrcFile, "#invalid_auto_src\n"))
        return Result::Error;
    if (!writeTextFile(loadedFile, "public func loaded() {}\n"))
        return Result::Error;

    const CommandLine cmdLine = makeSyntheticModuleFileCommand(CommandKind::Sema, moduleFile);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    if (Utf8(compiler.buildCfg().moduleNamespace) != "SetupNs")
        return Result::Error;
    if (Utf8(compiler.buildCfg().name) != "setup-artifact")
        return Result::Error;
    if (compiler.buildCfg().backendKind != Runtime::BuildCfgBackendKind::StaticLibrary)
        return Result::Error;

    const SourceFile* moduleSource = findCompilerFile(compiler, loadedFile);
    if (!moduleSource || !moduleSource->hasFlag(FileFlagsE::ModuleSrc))
        return Result::Error;

    const SourceFile* setupSource = findCompilerFile(compiler, moduleFile);
    if (!setupSource || !setupSource->hasFlag(FileFlagsE::Module))
        return Result::Error;

    if (findCompilerFile(compiler, autoSrcFile) != nullptr)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_ModuleFileSetupResolvesSwagStdImportFromConfiguredCompilerRoot)
{
    const ScopedTempTree tempTree("compiler_module_file_swag_std");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path compilerRoot = tempTree.root() / "compiler";
    const fs::path moduleDir    = tempTree.root() / "module";
    const fs::path moduleFile   = moduleDir / "module.swg";
    const fs::path sourceFile   = moduleDir / "src" / "main.swg";
    const fs::path importFile   = compilerRoot / "std" / ".output" / "dep" / "static-library" / "fast-debug" / "x86_64" / "api.swg";

    if (!writeTextFile(importFile, R"(#global export
public func depValue()->s32
{
    return 7
}
)"))
        return Result::Error;
    if (!writeTextFile(moduleFile, R"(#import("dep", location: "swag@std")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Main"
    cfg.backendKind = .Executable
}
)"))
        return Result::Error;
    if (!writeTextFile(sourceFile, R"(using Dep

public func mainValue()->s32
{
    return depValue()
}
)"))
        return Result::Error;

    const ScopedEnvVar swagPath("SWAG_PATH", compilerRoot.string());

    const CommandLine cmdLine = makeSyntheticModuleFileCommand(CommandKind::Sema, moduleFile);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    const SourceFile* importedSource = findCompilerFile(compiler, importFile);
    if (!importedSource || !importedSource->hasFlag(FileFlagsE::ImportedApi))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_ModuleFileSetupPrefersImportableSwagStdDependencyBackend)
{
    const ScopedTempTree tempTree("compiler_module_file_swag_std_backend_choice");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path compilerRoot         = tempTree.root() / "compiler";
    const fs::path moduleDir            = tempTree.root() / "module";
    const fs::path moduleFile           = moduleDir / "module.swg";
    const fs::path sourceFile           = moduleDir / "src" / "main.swg";
    const fs::path staticImportFile     = compilerRoot / "std" / ".output" / "dep" / "static-library" / "fast-debug" / "x86_64" / "api.swg";
    const fs::path executableImportFile = compilerRoot / "std" / ".output" / "dep" / "executable" / "fast-debug" / "x86_64" / "api.swg";

    if (!writeTextFile(staticImportFile, R"(#global export
public func depValue()->s32
{
    return 7
}
)"))
        return Result::Error;
    if (!writeTextFile(executableImportFile, R"(#global export
public func depValue()->s32
{
    return 9
}
)"))
        return Result::Error;
    if (!writeTextFile(moduleFile, R"(#import("dep", location: "swag@std")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Main"
    cfg.backendKind = .Executable
}
)"))
        return Result::Error;
    if (!writeTextFile(sourceFile, R"(using Dep

public func mainValue()->s32
{
    return depValue()
}
)"))
        return Result::Error;

    const ScopedEnvVar swagPath("SWAG_PATH", compilerRoot.string());

    CommandLine cmdLine = makeSyntheticModuleFileCommand(CommandKind::Sema, moduleFile);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    const SourceFile* importedStaticSource = findCompilerFile(compiler, staticImportFile);
    if (!importedStaticSource || !importedStaticSource->hasFlag(FileFlagsE::ImportedApi))
        return Result::Error;

    if (findCompilerFile(compiler, executableImportFile) != nullptr)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_ModuleFileSetupSeparatesImportedApiFromRequestedLinkBackend)
{
    const ScopedTempTree tempTree("compiler_module_file_swag_std_link_choice");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path compilerRoot     = tempTree.root() / "compiler";
    const fs::path moduleDir        = tempTree.root() / "module";
    const fs::path moduleFile       = moduleDir / "module.swg";
    const fs::path sourceFile       = moduleDir / "src" / "main.swg";
    const fs::path sharedImportDir  = compilerRoot / "std" / ".output" / "dep" / "shared-library" / "fast-debug" / "x86_64";
    const fs::path sharedImportFile = sharedImportDir / "api.swg";
    const fs::path staticImportDir  = compilerRoot / "std" / ".output" / "dep" / "static-library" / "fast-debug" / "x86_64";
    const fs::path staticImportFile = staticImportDir / "api.swg";

    if (!writeTextFile(sharedImportFile, R"(#global export
public func depValue()->s32
{
    return 7
}
)"))
        return Result::Error;
    if (!writeTextFile(staticImportFile, R"(#global export
public func depValue()->s32
{
    return 9
}
)"))
        return Result::Error;
    if (!writeTextFile(moduleFile, R"(#import("dep", location: "swag@std", link: "static-library")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Main"
    cfg.backendKind = .Executable
}
)"))
        return Result::Error;
    if (!writeTextFile(sourceFile, R"(using Dep

public func mainValue()->s32
{
    return depValue()
}
)"))
        return Result::Error;

    const ScopedEnvVar swagPath("SWAG_PATH", compilerRoot.string());

    CommandLine cmdLine = makeSyntheticModuleFileCommand(CommandKind::Sema, moduleFile);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    const SourceFile* importedSharedSource = findCompilerFile(compiler, sharedImportFile);
    if (!importedSharedSource || !importedSharedSource->hasFlag(FileFlagsE::ImportedApi))
        return Result::Error;

    if (findCompilerFile(compiler, staticImportFile) != nullptr)
        return Result::Error;

    const auto& linkDirs = compiler.importedDependencyLinkDirs();
    if (linkDirs.size() != 1)
        return Result::Error;
    if (!FileSystem::pathEquals(linkDirs.front(), staticImportDir))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_ImportedApiModulesResolveSwagStdFromEnvironment)
{
    const ScopedTempTree tempTree("compiler_import_api_module_swag_std");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path compilerRoot = tempTree.root() / "compiler";
    const fs::path sourceDir    = tempTree.root() / "sources";
    const fs::path sourceFile   = sourceDir / "main.swg";
    const fs::path importFile   = compilerRoot / "std" / ".output" / "dep" / "dep_env_probe" / "shared-library" / "fast-debug" / "x86_64" / "api.swg";

    if (!writeTextFile(importFile, R"(#global export
public func depValue()->s32
{
    return 7
}
)"))
        return Result::Error;
    if (!writeTextFile(sourceFile, R"(public func mainValue()->s32
{
    return 1
}
)"))
        return Result::Error;

    const ScopedEnvVar swagPath("SWAG_PATH", compilerRoot.string());

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Sema;
    cmdLine.runtime = false;
    cmdLine.silent  = true;
    cmdLine.files.insert(sourceFile);
    cmdLine.importApiModules.insert("dep_env_probe");
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    const SourceFile* importedSource = findCompilerFile(compiler, importFile);
    if (!importedSource || !importedSource->hasFlag(FileFlagsE::ImportedApi))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceSemaMirrorsExternalDependenciesIntoDepFolder)
{
    const ScopedTempTree tempTree("compiler_workspace_dep_mirror");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path compilerRoot   = tempTree.root() / "compiler";
    const fs::path workspaceDir   = tempTree.root() / "workspace";
    const fs::path appModuleDir   = workspaceDir / "modules" / "app";
    const fs::path coreConfigDir  = compilerRoot / "std" / ".output" / "core" / "shared-library" / "fast-debug" / "x86_64";
    const fs::path win32ConfigDir = compilerRoot / "std" / ".output" / "win32" / "export" / "fast-debug" / "x86_64";

    if (!writeTextFile(coreConfigDir / "core.swg", R"(#global export
public func coreValue()->s32
{
    return 7
}
)"))
        return Result::Error;
    if (!writeTextFile(coreConfigDir / "core.deps", R"(#import("win32", location: "swag@std")
)"))
        return Result::Error;
    if (!writeTextFile(coreConfigDir / "core.dll", "fake core dll"))
        return Result::Error;
    if (!writeTextFile(win32ConfigDir / "win32.swg", R"(#global export
public func win32Value()->s32
{
    return 3
}
)"))
        return Result::Error;
    if (!writeTextFile(win32ConfigDir / "win32.deps", ""))
        return Result::Error;

    if (!writeTextFile(appModuleDir / "module.swg", R"(#import("core", location: "swag@std")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "App"
    cfg.backendKind = .Executable
}
)"))
        return Result::Error;
    if (!writeTextFile(appModuleDir / "src" / "main.swg", R"(public func value()->s32
{
    return 1
}
)"))
        return Result::Error;

    const ScopedEnvVar swagPath("SWAG_PATH", compilerRoot.string());

    CommandLine      cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Sema, workspaceDir);
    CompilerInstance compiler(ctx.global(), cmdLine);
    if (compiler.run() != ExitCode::Success)
        return Result::Error;

    const fs::path copiedCoreDir  = workspaceDir / ".dep" / "core" / "shared-library" / "fast-debug" / "x86_64";
    const fs::path copiedWin32Dir = workspaceDir / ".dep" / "win32" / "export" / "fast-debug" / "x86_64";
    if (!fs::exists(copiedCoreDir / "core.swg"))
        return Result::Error;
    if (!fs::exists(copiedCoreDir / "core.deps"))
        return Result::Error;
    if (!fs::exists(copiedCoreDir / "core.dll"))
        return Result::Error;
    if (!fs::exists(copiedWin32Dir / "win32.swg"))
        return Result::Error;
    if (!fs::exists(copiedWin32Dir / "win32.deps"))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceSemaRefreshesMirroredDependencyArtifactWhenContentChangesWithSameTimestamp)
{
    const ScopedTempTree tempTree("compiler_workspace_dep_refresh");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path compilerRoot  = tempTree.root() / "compiler";
    const fs::path workspaceDir  = tempTree.root() / "workspace";
    const fs::path appModuleDir  = workspaceDir / "modules" / "app";
    const fs::path coreConfigDir = compilerRoot / "std" / ".output" / "core" / "shared-library" / "fast-debug" / "x86_64";

    if (!writeTextFile(coreConfigDir / "core.swg", R"(#global export
public func coreValue()->s32
{
    return 7
}
)"))
        return Result::Error;
    if (!writeTextFile(coreConfigDir / "core.deps", ""))
        return Result::Error;
    if (!writeTextFile(coreConfigDir / "core.dll", "fake core dll A"))
        return Result::Error;

    if (!writeTextFile(appModuleDir / "module.swg", R"(#import("core", location: "swag@std")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "App"
    cfg.backendKind = .Executable
}
)"))
        return Result::Error;
    if (!writeTextFile(appModuleDir / "src" / "main.swg", R"(public func value()->s32
{
    return 1
}
)"))
        return Result::Error;

    const ScopedEnvVar swagPath("SWAG_PATH", compilerRoot.string());

    CommandLine cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Sema, workspaceDir);
    {
        CompilerInstance compiler(ctx.global(), cmdLine);
        if (compiler.run() != ExitCode::Success)
            return Result::Error;
    }

    const fs::path          copiedCoreDll = workspaceDir / ".dep" / "core" / "shared-library" / "fast-debug" / "x86_64" / "core.dll";
    FileSystem::IoErrorInfo ioError;
    std::string             copiedDllContent;
    if (FileSystem::readTextFile(copiedCoreDll, copiedDllContent, ioError) != Result::Continue)
        return Result::Error;
    if (copiedDllContent != "fake core dll A")
        return Result::Error;

    std::error_code ec;
    const auto      copiedTime = fs::last_write_time(copiedCoreDll, ec);
    if (ec)
        return Result::Error;

    const fs::path sourceCoreDll = coreConfigDir / "core.dll";
    if (!writeTextFile(sourceCoreDll, "fake core dll B"))
        return Result::Error;

    ec.clear();
    const auto sourceSize = fs::file_size(sourceCoreDll, ec);
    if (ec)
        return Result::Error;
    ec.clear();
    const auto copiedSize = fs::file_size(copiedCoreDll, ec);
    if (ec || sourceSize != copiedSize)
        return Result::Error;

    ec.clear();
    fs::last_write_time(sourceCoreDll, copiedTime, ec);
    if (ec)
        return Result::Error;

    {
        CompilerInstance compiler(ctx.global(), cmdLine);
        if (compiler.run() != ExitCode::Success)
            return Result::Error;
    }

    copiedDllContent.clear();
    if (FileSystem::readTextFile(copiedCoreDll, copiedDllContent, ioError) != Result::Continue)
        return Result::Error;
    if (copiedDllContent != "fake core dll B")
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceImportedStdGenericRunRemainsStableAcrossRepeatedBuilds)
{
    const ScopedTempTree tempTree("compiler_workspace_imported_std_generic_repeat");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir = tempTree.root() / "workspace";
    const fs::path appModuleDir = workspaceDir / "modules" / "app";

    if (!writeTextFile(appModuleDir / "module.swg", R"(#import("core", location: "swag@std")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "App"
    cfg.backendKind = .Executable
}
)"))
        return Result::Error;

    if (!writeTextFile(appModuleDir / "src" / "main.swg", R"(using Core

func testBasic()->u64
{
    var table: HashTable'(u32, u64)
    table.add(1, 42)
    let found = table.tryFind(1)
    return found ? found.value : 0
}

#main
{
    @assert(testBasic() == 42)
}
)"))
        return Result::Error;

    const ScopedEnvVar swagPath("SWAG_PATH", Os::getExeFullName().parent_path().string());

    CommandLine cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Run, workspaceDir);
    cmdLine.runtime     = true;
    cmdLine.buildCfg    = "fast-compile";
    cmdLine.buildCfgExplicit = true;
    CommandLineParser::refreshBuildCfg(cmdLine);

    const fs::path appOutputDir = workspaceDir / ".output" / "app" / "executable" / "fast-compile";
    const fs::path appTempDir   = workspaceDir / ".tmp" / "app" / "executable" / "fast-compile";
    for (uint32_t iteration = 0; iteration < 40; iteration++)
    {
        std::error_code ec;
        fs::remove_all(appOutputDir, ec);
        if (ec)
            return Result::Error;

        ec.clear();
        fs::remove_all(appTempDir, ec);
        if (ec)
            return Result::Error;

        CompilerInstance compiler(ctx.global(), cmdLine);
        if (compiler.run() != ExitCode::Success)
            return Result::Error;
    }

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceExampleReleaseBuildRemainsStableAcrossRepeatedRebuilds)
{
    const ScopedTempTree tempTree("compiler_workspace_example_release_repeat");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir = tempTree.root() / "workspace";
    const fs::path aoc2015Dir   = workspaceDir / "modules" / "aoc2015";
    const fs::path aoc2016Dir   = workspaceDir / "modules" / "aoc2016";

    if (!copyDirectoryTree("bin/examples/modules/aoc2015", aoc2015Dir))
        return Result::Error;
    if (!copyDirectoryTree("bin/examples/modules/aoc2016", aoc2016Dir))
        return Result::Error;

    const ScopedEnvVar swagPath("SWAG_PATH", Os::getExeFullName().parent_path().string());

    CommandLine cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Build, workspaceDir);
    cmdLine.buildCfg    = "release";
    cmdLine.buildCfgExplicit = true;
    cmdLine.clear       = true;
    cmdLine.rebuild     = true;
    CommandLineParser::refreshBuildCfg(cmdLine);

    for (uint32_t iteration = 0; iteration < 12; iteration++)
    {
        CompilerInstance compiler(ctx.global(), cmdLine);
        if (compiler.run() != ExitCode::Success)
            return Result::Error;
    }

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_ModuleFileSetupKeepsExplicitCommandLineOverrides)
{
    const ScopedTempTree tempTree("compiler_module_file_cli_override");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path moduleDir  = tempTree.root() / "module";
    const fs::path moduleFile = moduleDir / "module.swg";
    const fs::path sourceFile = moduleDir / "src" / "main.swg";
    const fs::path outDir     = tempTree.root() / "cli-out";
    const fs::path workDir    = tempTree.root() / "cli-work";

    if (!writeTextFile(moduleFile, R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "SetupNs"
    cfg.name = "setup-artifact"
    cfg.backendKind = .StaticLibrary
    cfg.safetyGuards = .All
    cfg.sanity = true
    cfg.debugAllocator = true
    cfg.errorStackTrace = true
    cfg.backend.optimize = true
    cfg.backend.debugInfo = false
    cfg.backend.fpMathFma = false
    cfg.backend.fpMathNoNaN = false
    cfg.backend.fpMathNoInf = false
    cfg.backend.fpMathNoSignedZero = false
    cfg.outDir = "setup-out"
    cfg.workDir = "setup-work"
}
#load("./src/main.swg")
)"))
        return Result::Error;
    if (!writeTextFile(sourceFile, "public func helper() {}\n"))
        return Result::Error;

    CommandLine cmdLine;
    if (parseCommandLine(ctx, cmdLine,
                         {
                             "swc",
                             "test",
                             "--module-file",
                             moduleFile.string(),
                             "--build-cfg",
                             "release",
                             "--artifact-kind",
                             "executable",
                             "--artifact-name",
                             "cli-artifact",
                             "--module-namespace",
                             "CliNs",
                             "--out-dir",
                             outDir.string(),
                             "--work-dir",
                             workDir.string(),
                             "--no-optimize",
                         }) != Result::Continue)
        return Result::Error;
    cmdLine.runtime = false;
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    if (compiler.buildCfg().backendKind != Runtime::BuildCfgBackendKind::Executable)
        return Result::Error;
    if (Utf8(compiler.buildCfg().name) != "cli-artifact")
        return Result::Error;
    if (Utf8(compiler.buildCfg().moduleNamespace) != "CliNs")
        return Result::Error;
    if (!FileSystem::pathEquals(fs::path(Utf8(compiler.buildCfg().outDir).c_str()), outDir))
        return Result::Error;
    if (!FileSystem::pathEquals(fs::path(Utf8(compiler.buildCfg().workDir).c_str()), workDir))
        return Result::Error;

    if (compiler.buildCfg().safetyGuards != Runtime::SafetyWhat::None)
        return Result::Error;
    if (compiler.buildCfg().sanity)
        return Result::Error;
    if (compiler.buildCfg().debugAllocator)
        return Result::Error;
    if (compiler.buildCfg().errorStackTrace)
        return Result::Error;
    if (compiler.buildCfg().backend.optimize)
        return Result::Error;
    if (!compiler.buildCfg().backend.debugInfo)
        return Result::Error;
    if (!compiler.buildCfg().backend.fpMathFma)
        return Result::Error;
    if (!compiler.buildCfg().backend.fpMathNoNaN)
        return Result::Error;
    if (!compiler.buildCfg().backend.fpMathNoInf)
        return Result::Error;
    if (!compiler.buildCfg().backend.fpMathNoSignedZero)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceBuildAllowsConstExprCallsFromGeneratedSharedDependencyApi)
{
    const ScopedTempTree tempTree("compiler_workspace_generated_shared_constexpr");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir = tempTree.root() / "workspace";
    const fs::path depModuleDir = workspaceDir / "modules" / "dep";
    const fs::path useModuleDir = workspaceDir / "modules" / "use";

    if (!writeTextFile(depModuleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Dep"
    cfg.backendKind = .SharedLibrary
}
)"))
        return Result::Error;
    if (!writeTextFile(depModuleDir / "src" / "main.swg", R"(#global public
namespace Debug
{
    #[Swag.Macro]
    func depRequireNonNegative(value: #code s32, loc = #callerlocation)
    {
        if #inject(value) < 0 do
            @panic("negative value", loc)
    }
}

#[Swag.ConstExpr]
func depAbs(value: s32)->s32
{
    if value < 0 do
        return -value
    return value
}

func(T) depCheckedIdentity(value: T, original: s32)->T
{
    Debug.depRequireNonNegative(original)
    return value
}
)"))
        return Result::Error;

    if (!writeTextFile(useModuleDir / "module.swg", R"(#import("dep")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Use"
    cfg.backendKind = .Executable
}
)"))
        return Result::Error;
    if (!writeTextFile(useModuleDir / "src" / "main.swg", R"(using Dep

const IMPORTED_ABS = depAbs(-21)

func runtimeAbs(value: s32)->s32
{
    return depAbs(value)
}

func checked(value: s32)->s32
{
    return depCheckedIdentity(value, value)
}

func mainValue(value: s32)->s32
{
    #assert(IMPORTED_ABS == 21)
    return IMPORTED_ABS + runtimeAbs(value) + checked(value)
}

#main
{
    var runtimeValue = 5
    @assert(mainValue(runtimeValue) == 31)
}
)"))
        return Result::Error;

    const CommandLine cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Build, workspaceDir);

    CompilerInstance compiler(ctx.global(), cmdLine);
    if (compiler.run() != ExitCode::Success)
        return Result::Error;

    Utf8                    depApiContent;
    FileSystem::IoErrorInfo ioError;
    const fs::path          depApiFile = workspaceDir / ".output" / "dep" / "shared-library" / "fast-debug" / "x86_64" / "dep.swg";
    if (!fs::exists(depApiFile))
        return Result::Error;
    if (FileSystem::readTextFile(depApiFile, depApiContent, ioError) != Result::Continue)
        return Result::Error;
    if (!depApiContent.contains("#[Swag.ConstExpr]"))
        return Result::Error;
    if (!depApiContent.contains(R"(#[Swag.Foreign(module: "dep", function: "dep_abs", callconv: Swag.CallConv.Swag)])"))
        return Result::Error;
    if (!depApiContent.contains("func depAbs(value: s32)->s32;"))
        return Result::Error;
    if (!depApiContent.contains("func depRequireNonNegative(value: #code s32"))
        return Result::Error;
    if (!depApiContent.contains("func(T) depCheckedIdentity(value: T, original: s32)->T"))
        return Result::Error;
    if (!depApiContent.contains("Debug.depRequireNonNegative(original)"))
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceBuildUsesModuleSetupDependenciesAndSkipsIgnoredModules)
{
    const ScopedTempTree tempTree("compiler_workspace_build");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir     = tempTree.root() / "workspace";
    const fs::path depModuleDir     = workspaceDir / "modules" / "dep";
    const fs::path depLibModuleDir  = workspaceDir / "modules" / "deplib";
    const fs::path coreModuleDir    = workspaceDir / "modules" / "core";
    const fs::path ignoredModuleDir = workspaceDir / "modules" / "ignored";

    if (!writeTextFile(depModuleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Dep"
    cfg.backendKind = .Export
}
)"))
        return Result::Error;
    if (!writeTextFile(depModuleDir / "src" / "main.swg", R"(const PRIVATE_VALUE = 99
public const DEP_VALUE = 7

public func depFutureExport()->s32
{
    return DEP_VALUE
}

public func(T) depGenericIdentity(value: T)->T => value
)"))
        return Result::Error;
    if (!writeTextFile(depModuleDir / "src" / "public.swg", R"(#global public
// Exported comments must not leak in the generated module API

const DEP_PUBLIC_DEFAULT = 11 // Trailing comments must not leak either

const DEP_MULTI_A = 13, DEP_MULTI_B = 17
var DEP_IGNORED_GLOBAL = 59

namespace DepTools
{
    const DEP_NAMESPACE_A = 31
    const DEP_NAMESPACE_B = 37
}

/* Block comments must not leak */
fileprivate const DEP_FILE_PRIVATE = 23
moduleprivate const DEP_MODULE_PRIVATE = 29
)"))
        return Result::Error;
    if (!writeTextFile(depModuleDir / "src" / "public_more.swg", R"(#global public
namespace DepTools
{
    const DEP_NAMESPACE_C = 41
}

namespace DepTools.Deep
{
    const DEP_NAMESPACE_DEEP = 43
}

public struct DepIgnoredContainer
{
}

public impl DepIgnoredContainer
{
    const DEP_IMPL_VALUE = 47

    mtd run()
    {
        const DEP_LOCAL_VALUE = 53
    }
}
)"))
        return Result::Error;
    if (!writeTextFile(depModuleDir / "src" / "public_types.swg", R"(#global public
alias DepCount = s32

enum DepMode: s16
{
    Zero = 0
    Big  = 42
}

struct DepPair
{
    left:  DepCount
    right: s32
}

union DepValue
{
    asInt:   s32
    asFloat: f32
}

#[Swag.Opaque]
struct DepOpaque
{
    opaqueHead: u64
    opaqueTail: u32
}

interface IDepScore
{
    mtd score(value: s32)->s32;
}

namespace DepTools
{
    struct DepNamespaced
    {
        value: s16
    }
}
)"))
        return Result::Error;
    if (!writeTextFile(depModuleDir / "src" / "legacy.swg", R"(#global export
public func depLegacyValue()->s32
{
    return 5
}
)"))
        return Result::Error;

    if (!writeTextFile(depLibModuleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "DepLib"
    cfg.backendKind = .StaticLibrary
}
)"))
        return Result::Error;
    if (!writeTextFile(depLibModuleDir / "src" / "main.swg", R"(#global public
func depDouble(value: s32)->s32
{
    return value * 2
}

func depScale(value: s32)->s32
{
    return value * 4
}

func depScale(value: f32)->f32
{
    return value * 4
}

func depStringLength(text: string)->u64
{
    return @countof(text)
}

struct DepCalculator
{
    base: s32
}

impl DepCalculator
{
    func make(base: s32)->DepCalculator
    {
        return {base}
    }

    func resolve(value: s32)->s32
    {
        return value + 100
    }

    mtd const add(value: s32)->s32
    {
        return .base + value
    }

    mtd const addTwice(value: s32)->s32 => .add(value) + value
}
)"))
        return Result::Error;
    if (!writeTextFile(depLibModuleDir / "src" / "explicit_func.swg", R"(const PRIVATE_FACTOR = 3

public func depTriple(value: s32)->s32
{
    return value * PRIVATE_FACTOR
}
)"))
        return Result::Error;
    if (!writeTextFile(depLibModuleDir / "src" / "explicit_method.swg", R"(public impl DepCalculator
{
    mtd resolve(value: s32)->s32
    {
        return .base + value + 1000
    }

    mtd const add(value: f32)->f32
    {
        return cast(f32) .base + value
    }

    mtd const sub(value: s32)->s32
    {
        return .base - value
    }
}
)"))
        return Result::Error;
    if (!writeTextFile(depLibModuleDir / "src" / "public_inline.swg", R"(#global public
#[Swag.Macro]
func depMacroTwicePlus(value: s32, extra: s32 = 1)->s32
{
    let result = value * 2
    return result + extra
}

#[Swag.Mixin]
func depMixinAccumulateTwice(value: s32)
{
    let scaled = value * 2
    total += scaled
}

func(T) depMirror(value: T)->T => value
)"))
        return Result::Error;

    if (!writeTextFile(coreModuleDir / "module.swg", R"(#import("dep")
#import("deplib")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Core"
    cfg.backendKind = .StaticLibrary
}
)"))
        return Result::Error;
    if (!writeTextFile(coreModuleDir / "src" / "main.swg", R"(using Dep, DepLib

func keepDepScore(score: IDepScore)->IDepScore => score

public func coreValue()->s32
{
    var count: DepCount = 19
    var mode: DepMode = .Big
    var enumBonus = 0
    if mode == .Big
    {
        enumBonus = 42
    }
    var pair: DepPair
    pair.left  = 2
    pair.right = 5
    var value = DepValue{asInt: 0x1234}

    #assert(#sizeof(DepOpaque) == 16)
    #assert(#alignof(DepOpaque) == 8)
    var opaque: DepOpaque
    var namespaced: DepTools.DepNamespaced
    namespaced.value = 12
    var ignoredContainer: DepIgnoredContainer
    ignoredContainer.run()
    var total = 0
    depMixinAccumulateTwice(21)
    var calc = DepCalculator.make(5)

    return DEP_VALUE +
           depFutureExport() +
           depGenericIdentity(9) +
           DEP_PUBLIC_DEFAULT +
           DEP_MULTI_A +
           DEP_MULTI_B +
           DepTools.DEP_NAMESPACE_A +
           DepTools.DEP_NAMESPACE_B +
           DepTools.DEP_NAMESPACE_C +
           DepTools.Deep.DEP_NAMESPACE_DEEP +
           depLegacyValue() +
           count +
           pair.left +
           pair.right +
           enumBonus +
           value.asInt +
           depDouble(21) +
           depMirror(42) +
           depTriple(14) +
           cast(s32) depStringLength("core") +
           depMacroTwicePlus(20, 2) +
           depScale(cast(s32) 10) +
           cast(s32) depScale(cast(f32) 2) +
           DepCalculator.resolve(6) +
           calc.resolve(6) +
           calc.add(cast(s32) 7) +
           cast(s32) calc.add(cast(f32) 2) +
           calc.addTwice(7) +
           calc.sub(2) +
           total +
           namespaced.value +
           cast(s32) #sizeof(opaque)
}
)"))
        return Result::Error;

    if (!writeTextFile(ignoredModuleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Ignored"
    cfg.ignoreInWorkspace = true
}
)"))
        return Result::Error;
    if (!writeTextFile(ignoredModuleDir / "src" / "broken.swg", "#this_should_not_compile\n"))
        return Result::Error;

    CommandLine cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Sema, workspaceDir);

    CompilerInstance compiler(ctx.global(), cmdLine);
    if (compiler.run() != ExitCode::Success)
        return Result::Error;

    const fs::path depApiFile = workspaceDir / ".output" / "dep" / "export" / "fast-debug" / "x86_64" / "dep.swg";
    if (!fs::exists(depApiFile))
        return Result::Error;
    const fs::path depGeneratedDir = workspaceDir / ".output" / "dep" / "export" / "fast-debug" / "x86_64" / "__generated__";
    if (fs::exists(depGeneratedDir))
        return Result::Error;

    const fs::path legacyApiFile = workspaceDir / ".output" / "dep" / "export" / "fast-debug" / "x86_64" / "api.swg";
    if (fs::exists(legacyApiFile))
        return Result::Error;
    const fs::path copiedExportApiFile = workspaceDir / ".output" / "dep" / "export" / "fast-debug" / "x86_64" / "legacy.swg";
    if (!fs::exists(copiedExportApiFile))
        return Result::Error;
    const fs::path depLibApiFile = workspaceDir / ".output" / "deplib" / "static-library" / "fast-debug" / "x86_64" / "deplib.swg";
    if (!fs::exists(depLibApiFile))
        return Result::Error;
    const fs::path depLibGeneratedDir = workspaceDir / ".output" / "deplib" / "static-library" / "fast-debug" / "x86_64" / "__generated__";
    if (fs::exists(depLibGeneratedDir))
        return Result::Error;

    Utf8                    depApiContent;
    FileSystem::IoErrorInfo ioError;
    if (FileSystem::readTextFile(depApiFile, depApiContent, ioError) != Result::Continue)
        return Result::Error;
    if (!depApiContent.contains("#global public"))
        return Result::Error;
    if (!depApiContent.contains("const DEP_VALUE = 7"))
        return Result::Error;
    if (!depApiContent.contains("const DEP_PUBLIC_DEFAULT = 11"))
        return Result::Error;
    if (!depApiContent.contains("const DEP_MULTI_A = 13, DEP_MULTI_B = 17"))
        return Result::Error;
    if (!depApiContent.contains("const DEP_NAMESPACE_A = 31"))
        return Result::Error;
    if (!depApiContent.contains("const DEP_NAMESPACE_B = 37"))
        return Result::Error;
    if (!depApiContent.contains("const DEP_NAMESPACE_C = 41"))
        return Result::Error;
    if (!depApiContent.contains("const DEP_NAMESPACE_DEEP = 43"))
        return Result::Error;
    if (!depApiContent.contains("alias DepCount = s32"))
        return Result::Error;
    if (!depApiContent.contains("enum DepMode: s16"))
        return Result::Error;
    if (!depApiContent.contains("Big") || !depApiContent.contains("42"))
        return Result::Error;
    if (!depApiContent.contains("struct DepPair"))
        return Result::Error;
    if (!depApiContent.contains("union DepValue"))
        return Result::Error;
    if (!depApiContent.contains("struct DepOpaque"))
        return Result::Error;
    if (!depApiContent.contains("interface IDepScore"))
        return Result::Error;
    if (!depApiContent.contains("mtd score(value: s32)->s32;"))
        return Result::Error;
    if (!depApiContent.contains("struct DepNamespaced"))
        return Result::Error;
    if (!depApiContent.contains("swagOpaqueStorage"))
        return Result::Error;
    if (!depApiContent.contains("func depFutureExport()->s32"))
        return Result::Error;
    if (!depApiContent.contains("return DEP_VALUE"))
        return Result::Error;
    if (!depApiContent.contains("func(T) depGenericIdentity(value: T)->T"))
        return Result::Error;
    if (!depApiContent.contains("impl DepIgnoredContainer"))
        return Result::Error;
    if (!depApiContent.contains("mtd run()"))
        return Result::Error;
    if (!depApiContent.contains("DEP_LOCAL_VALUE = 53"))
        return Result::Error;
    if (depApiContent.contains("PRIVATE_VALUE"))
        return Result::Error;
    if (depApiContent.contains("DEP_FILE_PRIVATE"))
        return Result::Error;
    if (depApiContent.contains("DEP_MODULE_PRIVATE"))
        return Result::Error;
    if (depApiContent.contains("DEP_IGNORED_GLOBAL"))
        return Result::Error;
    if (depApiContent.contains("#[Swag.Foreign(\"dep\","))
        return Result::Error;
    if (depApiContent.contains("depLegacyValue"))
        return Result::Error;
    if (!depApiContent.contains("DEP_IMPL_VALUE = 47"))
        return Result::Error;
    if (depApiContent.contains("opaqueHead"))
        return Result::Error;
    if (depApiContent.contains("opaqueTail"))
        return Result::Error;
    if (depApiContent.contains("//") || depApiContent.contains("/*"))
        return Result::Error;
    Utf8 normalizedDepApiContent = depApiContent;
    normalizedDepApiContent.replace_loop("\r", "");
    const size_t depToolsPos = normalizedDepApiContent.find("namespace DepTools\n{\n    const DEP_NAMESPACE_A");
    if (depToolsPos == Utf8::npos)
        return Result::Error;
    const size_t depToolsDeepPos = normalizedDepApiContent.find("namespace Deep\n", depToolsPos + 1);
    if (depToolsDeepPos == Utf8::npos)
        return Result::Error;
    const size_t depNamespacedPos = normalizedDepApiContent.find("struct DepNamespaced");
    if (depNamespacedPos == Utf8::npos)
        return Result::Error;
    const size_t depNamespaceAPos    = normalizedDepApiContent.find("DEP_NAMESPACE_A");
    const size_t depNamespaceBPos    = normalizedDepApiContent.find("DEP_NAMESPACE_B");
    const size_t depNamespaceCPos    = normalizedDepApiContent.find("DEP_NAMESPACE_C");
    const size_t depNamespaceDeepPos = normalizedDepApiContent.find("DEP_NAMESPACE_DEEP");
    if (depNamespaceAPos == Utf8::npos || depNamespaceBPos == Utf8::npos || depNamespaceCPos == Utf8::npos || depNamespaceDeepPos == Utf8::npos)
        return Result::Error;
    if (!(depToolsPos < depNamespaceAPos &&
          depNamespaceAPos < depNamespaceBPos &&
          depNamespaceBPos < depNamespaceCPos &&
          depNamespaceCPos < depNamespacedPos &&
          depNamespaceCPos < depToolsDeepPos &&
          depToolsDeepPos < depNamespaceDeepPos))
        return Result::Error;
    if (normalizedDepApiContent.contains("\n\n\n"))
        return Result::Error;
    if (normalizedDepApiContent.contains("\npublic "))
        return Result::Error;
    Utf8 copiedExportApiContent;
    if (FileSystem::readTextFile(copiedExportApiFile, copiedExportApiContent, ioError) != Result::Continue)
        return Result::Error;
    if (!copiedExportApiContent.contains("public func depLegacyValue()->s32"))
        return Result::Error;

    Utf8 depLibApiContent;
    if (FileSystem::readTextFile(depLibApiFile, depLibApiContent, ioError) != Result::Continue)
        return Result::Error;
    if (!depLibApiContent.contains("#[Swag.Foreign(module: \"deplib\","))
        return Result::Error;
    if (depLibApiContent.contains("__swc_api_"))
        return Result::Error;
    if (!depLibApiContent.contains(R"(#[Swag.Foreign(module: "deplib", function: "dep_double", callconv: Swag.CallConv.Swag)])"))
        return Result::Error;
    if (!depLibApiContent.contains(R"(#[Swag.Foreign(module: "deplib", function: "dep_scale__s32", callconv: Swag.CallConv.Swag)])"))
        return Result::Error;
    if (!depLibApiContent.contains(R"(#[Swag.Foreign(module: "deplib", function: "dep_scale__f32", callconv: Swag.CallConv.Swag)])"))
        return Result::Error;
    if (!depLibApiContent.contains(R"(#[Swag.Foreign(module: "deplib", function: "dep_string_length", callconv: Swag.CallConv.Swag)])"))
        return Result::Error;
    if (!depLibApiContent.contains(R"(#[Swag.Foreign(module: "deplib", function: "dep_triple", callconv: Swag.CallConv.Swag)])"))
        return Result::Error;
    if (!depLibApiContent.contains(R"(#[Swag.Foreign(module: "deplib", function: "dep_calculator_make", callconv: Swag.CallConv.Swag)])"))
        return Result::Error;
    if (!depLibApiContent.contains(R"(#[Swag.Foreign(module: "deplib", function: "dep_calculator_resolve__s32_ret_s32", callconv: Swag.CallConv.Swag)])"))
        return Result::Error;
    if (!depLibApiContent.contains(R"(#[Swag.Foreign(module: "deplib", function: "dep_calculator_resolve__ref_dep_lib_dep_calculator_s32_ret_s32", callconv: Swag.CallConv.Swag)])"))
        return Result::Error;
    if (!depLibApiContent.contains(R"(#[Swag.Foreign(module: "deplib", function: "dep_calculator_add__s32", callconv: Swag.CallConv.Swag)])"))
        return Result::Error;
    if (!depLibApiContent.contains(R"(#[Swag.Foreign(module: "deplib", function: "dep_calculator_add__f32", callconv: Swag.CallConv.Swag)])"))
        return Result::Error;
    if (!depLibApiContent.contains(R"(#[Swag.Foreign(module: "deplib", function: "dep_calculator_add_twice", callconv: Swag.CallConv.Swag)])"))
        return Result::Error;
    if (!depLibApiContent.contains(R"(#[Swag.Foreign(module: "deplib", function: "dep_calculator_sub", callconv: Swag.CallConv.Swag)])"))
        return Result::Error;
    if (!depLibApiContent.contains("func depDouble(value: s32)->s32;"))
        return Result::Error;
    if (!depLibApiContent.contains("func(T) depMirror(value: T)->T"))
        return Result::Error;
    if (!depLibApiContent.contains("#[Swag.Macro]"))
        return Result::Error;
    if (!depLibApiContent.contains("func depMacroTwicePlus(value: s32, extra: s32 = 1)->s32"))
        return Result::Error;
    if (!depLibApiContent.contains("let result = value * 2"))
        return Result::Error;
    if (!depLibApiContent.contains("return result + extra"))
        return Result::Error;
    if (!depLibApiContent.contains("#[Swag.Mixin]"))
        return Result::Error;
    if (!depLibApiContent.contains("func depMixinAccumulateTwice(value: s32)"))
        return Result::Error;
    if (!depLibApiContent.contains("let scaled = value * 2"))
        return Result::Error;
    if (!depLibApiContent.contains("total += scaled"))
        return Result::Error;
    if (!depLibApiContent.contains("func depScale(value: s32)->s32;"))
        return Result::Error;
    if (!depLibApiContent.contains("func depScale(value: f32)->f32;"))
        return Result::Error;
    if (!depLibApiContent.contains("func depStringLength(text: string)->u64;"))
        return Result::Error;
    if (!depLibApiContent.contains("func depTriple(value: s32)->s32;"))
        return Result::Error;
    if (!depLibApiContent.contains("impl DepCalculator"))
        return Result::Error;
    if (!depLibApiContent.contains("func make(base: s32)->DepCalculator;"))
        return Result::Error;
    if (!depLibApiContent.contains("mtd const add(value: s32)->s32;"))
        return Result::Error;
    if (!depLibApiContent.contains("mtd const add(value: f32)->f32;"))
        return Result::Error;
    if (!depLibApiContent.contains("mtd const addTwice(value: s32)->s32;"))
        return Result::Error;
    if (!depLibApiContent.contains("mtd const sub(value: s32)->s32;"))
        return Result::Error;
    if (depLibApiContent.contains("PRIVATE_FACTOR"))
        return Result::Error;
    if (depLibApiContent.contains("return value * 2"))
        return Result::Error;
    if (depLibApiContent.contains("return value * PRIVATE_FACTOR"))
        return Result::Error;
    if (depLibApiContent.contains("return .base + value"))
        return Result::Error;
    if (depLibApiContent.contains("return .base - value"))
        return Result::Error;
    if (depLibApiContent.contains(R"(#[Swag.Foreign(module: "deplib", function: "dep_macro_twice_plus)"))
        return Result::Error;
    if (depLibApiContent.contains(R"(#[Swag.Foreign(module: "deplib", function: "dep_mixin_accumulate_twice)"))
        return Result::Error;
    if (depLibApiContent.contains(R"(#[Swag.Foreign(module: "deplib", function: "dep_mirror)"))
        return Result::Error;
    if (depLibApiContent.contains("\npublic "))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceBuildRejectsWholeFileExportNameConflict)
{
    const ScopedTempTree tempTree("compiler_workspace_export_name_conflict");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir = tempTree.root() / "workspace";
    const fs::path depModuleDir = workspaceDir / "modules" / "dep";

    if (!writeTextFile(depModuleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Dep"
    cfg.backendKind = .Export
}
)"))
        return Result::Error;
    if (!writeTextFile(depModuleDir / "src" / "dep.swg", R"(#global export
public const DEP_FILE_EXPORT = 1
)"))
        return Result::Error;
    if (!writeTextFile(depModuleDir / "src" / "public.swg", R"(#global public
const DEP_GENERATED_PUBLIC = 2
)"))
        return Result::Error;

    CommandLine cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Sema, workspaceDir);

    CompilerInstance compiler(ctx.global(), cmdLine);
    if (compiler.run() == ExitCode::Success)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceBuildFilterCompilesRequestedModuleAndDependencies)
{
    const ScopedTempTree tempTree("compiler_workspace_build_filter");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir = tempTree.root() / "workspace";
    const fs::path baseModuleDir = workspaceDir / "modules" / "base";
    const fs::path midModuleDir  = workspaceDir / "modules" / "mid";
    const fs::path appModuleDir  = workspaceDir / "modules" / "app";
    const fs::path otherModuleDir = workspaceDir / "modules" / "other";

    if (!writeTextFile(baseModuleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Base"
    cfg.backendKind = .Export
}
)"))
        return Result::Error;
    if (!writeTextFile(baseModuleDir / "src" / "main.swg", R"(#global public
func baseValue()->s32
{
    return 1
}
)"))
        return Result::Error;

    if (!writeTextFile(midModuleDir / "module.swg", R"(#import("base")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Mid"
    cfg.backendKind = .Export
}
)"))
        return Result::Error;
    if (!writeTextFile(midModuleDir / "src" / "main.swg", R"(#global public
func midValue()->s32
{
    return 2
}
)"))
        return Result::Error;

    if (!writeTextFile(appModuleDir / "module.swg", R"(#import("mid")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "App"
    cfg.backendKind = .Export
}
)"))
        return Result::Error;
    if (!writeTextFile(appModuleDir / "src" / "main.swg", R"(#global public
func appValue()->s32
{
    return 3
}
)"))
        return Result::Error;

    if (!writeTextFile(otherModuleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Other"
    cfg.backendKind = .Export
}
)"))
        return Result::Error;
    if (!writeTextFile(otherModuleDir / "src" / "main.swg", R"(#global public
func otherValue()->s32
{
    return 4
}
)"))
        return Result::Error;

    CommandLine cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Sema, workspaceDir);
    cmdLine.workspaceModuleFilter = "app";
    CommandLineParser::refreshBuildCfg(cmdLine);

    CompilerInstance compiler(ctx.global(), cmdLine);
    if (compiler.run() != ExitCode::Success)
        return Result::Error;

    const fs::path baseApiFile  = workspaceDir / ".output" / "base" / "export" / "fast-debug" / "x86_64" / "base.swg";
    const fs::path midApiFile   = workspaceDir / ".output" / "mid" / "export" / "fast-debug" / "x86_64" / "mid.swg";
    const fs::path appApiFile   = workspaceDir / ".output" / "app" / "export" / "fast-debug" / "x86_64" / "app.swg";
    const fs::path otherApiFile = workspaceDir / ".output" / "other" / "export" / "fast-debug" / "x86_64" / "other.swg";

    if (!fs::exists(baseApiFile))
        return Result::Error;
    if (!fs::exists(midApiFile))
        return Result::Error;
    if (!fs::exists(appApiFile))
        return Result::Error;
    if (fs::exists(otherApiFile))
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceBuildRejectsPublicStructWithModuleprivateFieldInGeneratedApi)
{
    const ScopedTempTree tempTree("compiler_workspace_invalid_public_type");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir = tempTree.root() / "workspace";
    const fs::path depModuleDir = workspaceDir / "modules" / "dep";

    if (!writeTextFile(depModuleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Dep"
    cfg.backendKind = .Export
}
)"))
        return Result::Error;

    if (!writeTextFile(depModuleDir / "src" / "main.swg", R"(#global public
struct BadExport
{
    moduleprivate hidden: s32
}
)"))
        return Result::Error;

    const CommandLine cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Sema, workspaceDir);

    CompilerInstance compiler(ctx.global(), cmdLine);
    if (compiler.run() == ExitCode::Success)
        return Result::Error;

    const fs::path depApiFile = workspaceDir / ".output" / "dep" / "export" / "fast-debug" / "x86_64" / "dep.swg";
    if (fs::exists(depApiFile))
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceBuildRejectsExplicitPublicGlobalVariableInGeneratedApi)
{
    const ScopedTempTree tempTree("compiler_workspace_invalid_public_global");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir = tempTree.root() / "workspace";
    const fs::path depModuleDir = workspaceDir / "modules" / "dep";

    if (!writeTextFile(depModuleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Dep"
    cfg.backendKind = .Export
}
)"))
        return Result::Error;

    if (!writeTextFile(depModuleDir / "src" / "main.swg", R"(public var BadExport: s32 = 1
)"))
        return Result::Error;

    const CommandLine cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Sema, workspaceDir);

    CompilerInstance compiler(ctx.global(), cmdLine);
    if (compiler.run() == ExitCode::Success)
        return Result::Error;

    const fs::path depApiFile = workspaceDir / ".output" / "dep" / "export" / "fast-debug" / "x86_64" / "dep.swg";
    if (fs::exists(depApiFile))
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceBuildRejectsPublicInterfaceReferencingPrivateTypeInGeneratedApi)
{
    const ScopedTempTree tempTree("compiler_workspace_invalid_public_interface");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir = tempTree.root() / "workspace";
    const fs::path depModuleDir = workspaceDir / "modules" / "dep";

    if (!writeTextFile(depModuleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Dep"
    cfg.backendKind = .Export
}
)"))
        return Result::Error;

    if (!writeTextFile(depModuleDir / "src" / "main.swg", R"(struct HiddenArg
{
    value: s32
}

public interface BadExport
{
    mtd score(arg: HiddenArg)->s32;
}
)"))
        return Result::Error;

    const CommandLine cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Sema, workspaceDir);

    CompilerInstance compiler(ctx.global(), cmdLine);
    if (compiler.run() == ExitCode::Success)
        return Result::Error;

    const fs::path depApiFile = workspaceDir / ".output" / "dep" / "export" / "fast-debug" / "x86_64" / "dep.swg";
    if (fs::exists(depApiFile))
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_FormatSummaryLineShowsWrittenFilesBeforeTime)
{
    Stats::resetCommandMetrics();

    Stats& stats = Stats::get();
    stats.numFiles.store(3, std::memory_order_relaxed);
    stats.timeTotal.store(1'000'000'000, std::memory_order_relaxed);
    stats.numFormatRewrittenFiles.store(2, std::memory_order_relaxed);

    CommandLine cmdLine;
    cmdLine.command  = CommandKind::Format;
    cmdLine.logColor = false;

    const TaskContext                   formatCtx(ctx.global(), cmdLine);
    const TimedActionLog::StatsSnapshot snapshot        = TimedActionLog::StatsSnapshot::capture();
    const Utf8                          summaryLine     = TimedActionLog::formatSummaryLine(formatCtx, snapshot);
    const Utf8                          expectedTime    = Utf8Helper::toNiceTime(1.0);
    const Utf8                          expectedWritten = Utf8Helper::countWithLabel(2, "written file");
    const size_t                        completedPos    = summaryLine.find("Completed");
    const size_t                        timePos         = summaryLine.find(expectedTime);
    const size_t                        writtenPos      = summaryLine.find(expectedWritten);

    Stats::resetCommandMetrics();

    if (completedPos == Utf8::npos || timePos == Utf8::npos || writtenPos == Utf8::npos)
        return Result::Error;
    if (!(completedPos < writtenPos && writtenPos < timePos))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_FormatCommandHeaderLineUsesWorkspaceScope)
{
    CommandLine cmdLine;
    cmdLine.command       = CommandKind::Build;
    cmdLine.workspacePath = "bin/std";
    cmdLine.logColor      = false;

    const TaskContext headerCtx(ctx.global(), cmdLine);
    const Utf8        headerLine = TimedActionLog::formatCommandHeaderLine(headerCtx);

    if (headerLine.find("build workspace std") == Utf8::npos)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_FormatCommandHeaderLineUsesFileScope)
{
    CommandLine cmdLine;
    cmdLine.command  = CommandKind::Syntax;
    cmdLine.logColor = false;
    cmdLine.directories.insert("bin/tests/parser");

    const TaskContext headerCtx(ctx.global(), cmdLine);
    const Utf8        headerLine = TimedActionLog::formatCommandHeaderLine(headerCtx);

    if (headerLine.find("syntax files in bin/tests/parser") == Utf8::npos)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceBuildSkipsUnchangedModuleAndRebuildFlagForcesRecompile)
{
    const ScopedTempTree tempTree("compiler_workspace_skip_and_rebuild");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir = tempTree.root() / "workspace";
    const fs::path moduleDir    = workspaceDir / "modules" / "dep";
    const fs::path sourceFile   = moduleDir / "src" / "main.swg";
    const fs::path artifactPath = workspaceDir / ".output" / "dep" / "export" / "fast-debug" / "x86_64" / "dep.swg";
    const fs::path manifestPath = artifactPath.parent_path() / ".swc-artifacts";

    if (!writeTextFile(moduleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Dep"
    cfg.backendKind = .Export
}
)"))
        return Result::Error;
    if (!writeTextFile(sourceFile, "public const VALUE: s32 = 1\n"))
        return Result::Error;

    CommandLine cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Build, workspaceDir);
    cmdLine.runtime     = true;

    CompilerInstance firstCompiler(ctx.global(), cmdLine);
    if (firstCompiler.run() != ExitCode::Success)
        return Result::Error;
    if (!fs::exists(artifactPath) || !fs::exists(manifestPath))
        return Result::Error;

    fs::file_time_type firstTime;
    if (!tryGetPathWriteTime(firstTime, artifactPath))
        return Result::Error;

    waitForTimestampTick();

    CompilerInstance secondCompiler(ctx.global(), cmdLine);
    if (secondCompiler.run() != ExitCode::Success)
        return Result::Error;

    fs::file_time_type secondTime;
    if (!tryGetPathWriteTime(secondTime, artifactPath))
        return Result::Error;
    if (secondTime != firstTime)
        return Result::Error;

    waitForTimestampTick();

    cmdLine.rebuild = true;
    CompilerInstance thirdCompiler(ctx.global(), cmdLine);
    if (thirdCompiler.run() != ExitCode::Success)
        return Result::Error;

    fs::file_time_type thirdTime;
    if (!tryGetPathWriteTime(thirdTime, artifactPath))
        return Result::Error;
    if (thirdTime <= secondTime)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceBuildRecompilesWhenModuleSourceChanges)
{
    const ScopedTempTree tempTree("compiler_workspace_rebuild_on_source_change");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir = tempTree.root() / "workspace";
    const fs::path moduleDir    = workspaceDir / "modules" / "dep";
    const fs::path sourceFile   = moduleDir / "src" / "main.swg";
    const fs::path artifactPath = workspaceDir / ".output" / "dep" / "export" / "fast-debug" / "x86_64" / "dep.swg";

    if (!writeTextFile(moduleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Dep"
    cfg.backendKind = .Export
}
)"))
        return Result::Error;
    if (!writeTextFile(sourceFile, "public const VALUE: s32 = 1\n"))
        return Result::Error;

    CommandLine cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Build, workspaceDir);
    cmdLine.runtime     = true;

    CompilerInstance firstCompiler(ctx.global(), cmdLine);
    if (firstCompiler.run() != ExitCode::Success)
        return Result::Error;

    fs::file_time_type firstTime;
    if (!tryGetPathWriteTime(firstTime, artifactPath))
        return Result::Error;

    waitForTimestampTick();
    if (!writeTextFile(sourceFile, "public const VALUE: s32 = 2\n"))
        return Result::Error;

    CompilerInstance secondCompiler(ctx.global(), cmdLine);
    if (secondCompiler.run() != ExitCode::Success)
        return Result::Error;

    fs::file_time_type secondTime;
    if (!tryGetPathWriteTime(secondTime, artifactPath))
        return Result::Error;
    if (secondTime <= firstTime)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceBuildRecompilesWhenDependencyChanges)
{
    const ScopedTempTree tempTree("compiler_workspace_rebuild_on_dependency_change");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir   = tempTree.root() / "workspace";
    const fs::path depModuleDir   = workspaceDir / "modules" / "dep";
    const fs::path useModuleDir   = workspaceDir / "modules" / "use";
    const fs::path depSourceFile  = depModuleDir / "src" / "main.swg";
    const fs::path useArtifact    = workspaceDir / ".output" / "use" / "export" / "fast-debug" / "x86_64" / "use.swg";

    if (!writeTextFile(depModuleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Dep"
    cfg.backendKind = .Export
}
)"))
        return Result::Error;
    if (!writeTextFile(depSourceFile, "public const VALUE: s32 = 1\n"))
        return Result::Error;

    if (!writeTextFile(useModuleDir / "module.swg", R"(#import("dep")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Use"
    cfg.backendKind = .Export
}
)"))
        return Result::Error;
    if (!writeTextFile(useModuleDir / "src" / "main.swg", R"(using Dep

public func readValue()->s32
{
    return VALUE
}
)"))
        return Result::Error;

    CommandLine cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Build, workspaceDir);
    cmdLine.runtime     = true;

    CompilerInstance firstCompiler(ctx.global(), cmdLine);
    if (firstCompiler.run() != ExitCode::Success)
        return Result::Error;

    fs::file_time_type firstTime;
    if (!tryGetPathWriteTime(firstTime, useArtifact))
        return Result::Error;

    waitForTimestampTick();
    if (!writeTextFile(depSourceFile, "public const VALUE: s32 = 2\n"))
        return Result::Error;

    CompilerInstance secondCompiler(ctx.global(), cmdLine);
    if (secondCompiler.run() != ExitCode::Success)
        return Result::Error;

    fs::file_time_type secondTime;
    if (!tryGetPathWriteTime(secondTime, useArtifact))
        return Result::Error;
    if (secondTime <= firstTime)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceBuildRecompilesWhenCompilerTimestampChanges)
{
    const ScopedTempTree tempTree("compiler_workspace_rebuild_on_compiler_change");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir = tempTree.root() / "workspace";
    const fs::path moduleDir    = workspaceDir / "modules" / "dep";
    const fs::path artifactPath = workspaceDir / ".output" / "dep" / "export" / "fast-debug" / "x86_64" / "dep.swg";
    const fs::path exePath      = Os::getExeFullName();

    if (!writeTextFile(moduleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Dep"
    cfg.backendKind = .Export
}
)"))
        return Result::Error;
    if (!writeTextFile(moduleDir / "src" / "main.swg", "public const VALUE: s32 = 1\n"))
        return Result::Error;

    CommandLine cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Build, workspaceDir);
    cmdLine.runtime     = true;

    CompilerInstance firstCompiler(ctx.global(), cmdLine);
    if (firstCompiler.run() != ExitCode::Success)
        return Result::Error;

    fs::file_time_type firstTime;
    if (!tryGetPathWriteTime(firstTime, artifactPath))
        return Result::Error;

    const ScopedPathWriteTime restoreExeTime(exePath);
    if (!setPathWriteTime(exePath, firstTime + std::chrono::seconds(10)))
        return Result::Error;

    waitForTimestampTick();

    CompilerInstance secondCompiler(ctx.global(), cmdLine);
    if (secondCompiler.run() != ExitCode::Success)
        return Result::Error;

    fs::file_time_type secondTime;
    if (!tryGetPathWriteTime(secondTime, artifactPath))
        return Result::Error;
    if (secondTime <= firstTime)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceBuildAllowsBorrowedIndirectCallsFromGeneratedSharedDependencyApi)
{
    const ScopedTempTree tempTree("compiler_workspace_generated_shared_indirect");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir = tempTree.root() / "workspace";
    const fs::path depModuleDir = workspaceDir / "modules" / "dep";
    const fs::path useModuleDir = workspaceDir / "modules" / "use";

    if (!writeTextFile(depModuleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Dep"
    cfg.backendKind = .SharedLibrary
}
)"))
        return Result::Error;
    if (!writeTextFile(depModuleDir / "src" / "main.swg", R"(#global public
func countString(value: string)->u64
{
    return @countof(value)
}

func echoString(value: string)->string
{
    return value
}
)"))
        return Result::Error;

    if (!writeTextFile(useModuleDir / "module.swg", R"(#import("dep")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.moduleNamespace = "Use"
    cfg.backendKind = .Executable
}
)"))
        return Result::Error;
    if (!writeTextFile(useModuleDir / "src" / "main.swg", R"(using Dep

func mainValue()->u64
{
    let echoed = echoString("abcd")
    @assert(@countof(echoed) == 4)
    @assert(countString(echoed) == 4)
    return countString(#file)
}

#main
{
    @assert(mainValue() > 0)
}
)"))
        return Result::Error;

    CommandLine cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Build, workspaceDir);
    cmdLine.runtime     = true;

    CompilerInstance compiler(ctx.global(), cmdLine);
    if (compiler.run() != ExitCode::Success)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_WorkspaceRunExecutableUsesDllAndSharesRuntimeContextAcrossDependencies)
{
    const ScopedTempTree tempTree("compiler_workspace_runtime_context_exe_uses_dll");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path workspaceDir      = tempTree.root() / "workspace";
    const fs::path baseModuleDir     = workspaceDir / "modules" / "runtime_context_base_static";
    const fs::path dllModuleDir      = workspaceDir / "modules" / "runtime_context_bridge_dll";
    const fs::path directModuleDir   = workspaceDir / "modules" / "runtime_context_direct_static";
    const fs::path consumerModuleDir = workspaceDir / "modules" / "consumer_exe";

    if (!writeTextFile(baseModuleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "RuntimeCtxBase"
    cfg.backendKind = .StaticLibrary
}
)"))
        return Result::Error;
    if (!writeTextFile(baseModuleDir / "src" / "main.swg", R"(public const CTX_BASE_INIT_FLAG    = 0x0001'u64
public const CTX_BASE_PREMAIN_FLAG = 0x0002'u64
public const CTX_BASE_DROP_FLAG    = 0x0004'u64

#init
{
    @assert(@getcontext().allocator != null)
    @getcontext().user1 |= CTX_BASE_INIT_FLAG
    @getcontext().user3 += 1
}

#premain
{
    @assert((@getcontext().user1 & CTX_BASE_INIT_FLAG) != 0)
    @getcontext().user1 |= CTX_BASE_PREMAIN_FLAG
    @getcontext().user3 += 0x100
}

#drop
{
    @assert(@getcontext().user0 == 43)
    @getcontext().user1 |= CTX_BASE_DROP_FLAG
}

public func ctxBaseReadContext()->u64
{
    @assert(@getcontext().allocator != null)
    return @getcontext().user0
}

public func ctxBaseContextMarker()->u64
{
    @assert(@getcontext().allocator != null)
    return @getcontext().user2
}

public func ctxBaseInitCount()->u64
{
    @assert(@getcontext().allocator != null)
    return @getcontext().user3 & 0xff
}

public func ctxBasePreMainCount()->u64
{
    @assert(@getcontext().allocator != null)
    return (@getcontext().user3 >> 8) & 0xff
}
)"))
        return Result::Error;

    if (!writeTextFile(dllModuleDir / "module.swg", R"(#import("runtime_context_base_static", link: "static-library")
#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "RuntimeCtxDll"
    cfg.backendKind = .SharedLibrary
}
)"))
        return Result::Error;
    if (!writeTextFile(dllModuleDir / "src" / "main.swg", R"(using RuntimeCtxBase

public const CTX_SHARED_INIT_FLAG    = 0x0008'u64
public const CTX_SHARED_PREMAIN_FLAG = 0x0010'u64
public const CTX_SHARED_DROP_FLAG    = 0x0020'u64

#init
{
    @assert((@getcontext().user1 & CTX_BASE_INIT_FLAG) != 0)
    @assert(@getcontext().allocator != null)
    @getcontext().user1 |= CTX_SHARED_INIT_FLAG
}

#premain
{
    @assert((@getcontext().user1 & CTX_BASE_PREMAIN_FLAG) != 0)
    @getcontext().user1 |= CTX_SHARED_PREMAIN_FLAG
}

#drop
{
    @assert(@getcontext().user0 == 43)
    @getcontext().user1 |= CTX_SHARED_DROP_FLAG
}

public func ctxSharedReadContext()->u64
{
    return ctxBaseReadContext()
}

public func ctxSharedContextMarker()->u64
{
    return ctxBaseContextMarker()
}
)"))
        return Result::Error;

    if (!writeTextFile(directModuleDir / "module.swg", R"(#run
{
    let cfg = @compiler.getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "RuntimeCtxDirect"
    cfg.backendKind = .StaticLibrary
}
)"))
        return Result::Error;
    if (!writeTextFile(directModuleDir / "src" / "main.swg", R"(public const CTX_DIRECT_INIT_FLAG    = 0x0040'u64
public const CTX_DIRECT_PREMAIN_FLAG = 0x0080'u64
public const CTX_DIRECT_DROP_FLAG    = 0x0100'u64

#init
{
    @assert(@getcontext().allocator != null)
    @getcontext().user1 |= CTX_DIRECT_INIT_FLAG
}

#premain
{
    @assert((@getcontext().user1 & CTX_DIRECT_INIT_FLAG) != 0)
    @getcontext().user1 |= CTX_DIRECT_PREMAIN_FLAG
}

#drop
{
    @assert(@getcontext().user0 == 43)
    @getcontext().user1 |= CTX_DIRECT_DROP_FLAG
}

public func ctxDirectReadContext()->u64
{
    @assert(@getcontext().allocator != null)
    return @getcontext().user0
}

public func ctxDirectContextMarker()->u64
{
    @assert(@getcontext().allocator != null)
    return @getcontext().user2
}
)"))
        return Result::Error;

    if (!writeTextFile(consumerModuleDir / "module.swg", R"(#import("runtime_context_bridge_dll")
#import("runtime_context_base_static", link: "static-library")
#import("runtime_context_direct_static", link: "static-library")
#run
{
    // Keep the workspace rooted at an executable so we validate direct exe -> dll usage.
    let cfg = @compiler.getBuildCfg()
    cfg.embeddedImports = true
    cfg.moduleNamespace = "ConsumerExe"
    cfg.backendKind = .Executable
}
)"))
        return Result::Error;
    if (!writeTextFile(consumerModuleDir / "src" / "main.swg", R"(using RuntimeCtxDll, RuntimeCtxBase, RuntimeCtxDirect

#init
{
    @assert((@getcontext().user1 & CTX_SHARED_INIT_FLAG) != 0)
    @assert((@getcontext().user1 & CTX_DIRECT_INIT_FLAG) != 0)
}

#premain
{
    @assert((@getcontext().user1 & CTX_SHARED_PREMAIN_FLAG) != 0)
    @assert((@getcontext().user1 & CTX_DIRECT_PREMAIN_FLAG) != 0)
}

#drop
{
    var cxt = dref @getcontext()
    cxt.user0 = 43
    @setcontext(cxt)
}

#main
{
    var cxt = dref @getcontext()
    cxt.user0 = 42
    cxt.user2 = cast(u64) @getcontext()
    @setcontext(cxt)
    let expectedContext = @getcontext().user2
    @assert(ctxBaseReadContext() == 42)
    @assert(ctxSharedReadContext() == 42)
    @assert(ctxDirectReadContext() == 42)
    @assert(ctxBaseContextMarker() == expectedContext)
    @assert(ctxSharedContextMarker() == expectedContext)
    @assert(ctxDirectContextMarker() == expectedContext)
    @assert(ctxBaseInitCount() == 2)
    @assert(ctxBasePreMainCount() == 2)
}
)"))
        return Result::Error;

    CommandLine cmdLine = makeSyntheticWorkspaceCommand(CommandKind::Run, workspaceDir);
    cmdLine.runtime     = true;

    CompilerInstance compiler(ctx.global(), cmdLine);
    if (compiler.run() != ExitCode::Success)
        return Result::Error;

    if (!fs::exists(workspaceDir / ".output" / "runtime_context_base_static" / "static-library" / "fast-debug" / "x86_64" / "runtime_context_base_static.lib"))
        return Result::Error;
    if (!fs::exists(workspaceDir / ".output" / "runtime_context_bridge_dll" / "shared-library" / "fast-debug" / "x86_64" / "runtime_context_bridge_dll.dll"))
        return Result::Error;
    if (!fs::exists(workspaceDir / ".output" / "runtime_context_direct_static" / "static-library" / "fast-debug" / "x86_64" / "runtime_context_direct_static.lib"))
        return Result::Error;
    if (!fs::exists(workspaceDir / ".output" / "consumer_exe" / "executable" / "fast-debug" / "x86_64" / "consumer_exe.exe"))
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_FormatDryRunDoesNotRewriteChangedFile)
{
    const ScopedTempTree tempTree("compiler_format_dry_run_no_rewrite");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path sourcePath = tempTree.root() / "main.swg";
    const fs::path configPath = tempTree.root() / ".swc-format";
    const Utf8     source     = "#assert(0xdead == 0xdead)\n";
    if (!writeTextFile(sourcePath, source))
        return Result::Error;
    if (!writeTextFile(configPath, "hex-literal-case = upper\n"))
        return Result::Error;

    CommandLine cmdLine;
    cmdLine.command  = CommandKind::Format;
    cmdLine.dryRun   = true;
    cmdLine.runtime  = false;
    cmdLine.silent   = true;
    cmdLine.logColor = false;
    cmdLine.files.insert(sourcePath);

    CompilerInstance compiler(ctx.global(), cmdLine);
    if (compiler.run() != ExitCode::Success)
        return Result::Error;

    std::ifstream stream(sourcePath, std::ios::binary);
    if (!stream.is_open())
        return Result::Error;

    const std::string content((std::istreambuf_iterator(stream)), std::istreambuf_iterator<char>());
    if (content != source)
        return Result::Error;
    if (Stats::get().numFormatRewrittenFiles.load(std::memory_order_relaxed) != 1)
        return Result::Error;

    Stats::resetCommandMetrics();
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_FormatOptionsLoaderMergesHierarchy)
{
    const ScopedTempTree tempTree("compiler_format_options_loader");
    if (!tempTree.ready())
        return Result::Error;

    const fs::path rootConfig    = tempTree.root() / ".swc-format";
    const fs::path projectConfig = tempTree.root() / "project" / ".swc-format";
    const fs::path packageConfig = tempTree.root() / "project" / "pkg" / ".swc-format";
    const fs::path sourcePath    = tempTree.root() / "project" / "pkg" / "sub" / "main.swg";

    if (!writeTextFile(rootConfig, R"(# The temp root establishes a deterministic baseline.
preserve-bom = false
preserve-trailing-whitespace = true
insert-final-newline = false
indent-width = 3
indent-style = tabs
end-of-line-style = crlf
)"))
        return Result::Error;
    if (!writeTextFile(projectConfig, R"(insert-final-newline = true
indent-width = 2
)"))
        return Result::Error;
    if (!writeTextFile(packageConfig, R"(# More specific folders override only the settings they care about.
preserve-trailing-whitespace = false
indent-width = 6
indent-style = spaces
end-of-line-style = lf
)"))
        return Result::Error;
    if (!writeTextFile(sourcePath, "func main() {}\n"))
        return Result::Error;

    FormatOptions       formatOptions;
    const uint64_t      errorsBefore = Stats::getNumErrors();
    FormatOptionsLoader loader(ctx);
    if (loader.resolve(sourcePath, formatOptions) != Result::Continue)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    if (formatOptions.preserveBom.value_or(true))
        return Result::Error;
    if (formatOptions.preserveTrailingWhitespace.value_or(true))
        return Result::Error;
    if (!formatOptions.insertFinalNewline.value_or(false))
        return Result::Error;
    if (formatOptions.indentWidth != 6)
        return Result::Error;
    if (formatOptions.indentStyle != FormatIndentStyle::Spaces)
        return Result::Error;
    if (formatOptions.endOfLineStyle != FormatEndOfLineStyle::Lf)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_FormatterAppliesFormatOptions)
{
    static constexpr std::string_view SOURCE = "\xEF\xBB\xBF"
                                               "func A() {\r\n\tlet a  = 1  \r\n\tlet b = 2\t \r\n}";

    FormatOptions formatOptions;
    formatOptions.preserveBom                = false;
    formatOptions.preserveTrailingWhitespace = false;
    formatOptions.insertFinalNewline         = true;
    formatOptions.indentWidth                = 2;
    formatOptions.indentStyle                = FormatIndentStyle::Spaces;
    formatOptions.endOfLineStyle             = FormatEndOfLineStyle::Lf;

    Utf8 formatted;
    SWC_RESULT(formatSourceText(ctx.global(), SOURCE, formatOptions, formatted));

    if (formatted != "func A() {\n  let a  = 1\n  let b = 2\n}\n")
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_FormatterPreservesTriviaAndInfersFinalNewlineStyle)
{
    static constexpr std::string_view SOURCE = "\xEF\xBB\xBF"
                                               "func A() {\r\n\tlet a = 1  \r\n}";

    FormatOptions formatOptions;
    formatOptions.preserveBom                = true;
    formatOptions.preserveTrailingWhitespace = true;
    formatOptions.insertFinalNewline         = true;
    formatOptions.indentStyle                = FormatIndentStyle::Preserve;
    formatOptions.endOfLineStyle             = FormatEndOfLineStyle::Preserve;

    Utf8 formatted;
    SWC_RESULT(formatSourceText(ctx.global(), SOURCE, formatOptions, formatted));

    if (formatted != "\xEF\xBB\xBF"
                     "func A() {\r\n\tlet a = 1  \r\n}\r\n")
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
