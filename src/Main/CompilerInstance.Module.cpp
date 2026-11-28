#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Backend/Linker/Linker.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/RuntimeName.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/ModuleApi/ModuleApi.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Sema/Helpers/SemaBodyCache.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Compiler/Verify.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerCache.h"
#include "Main/CompilerCacheStore.h"
#include "Main/ExternalModuleManager.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Main/Version.h"
#include "Main/WorkspaceLayout.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Math/Hash.h"
#include "Support/Math/Sha256.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/Logger.h"
#include "Support/Report/ScopedTimedLog.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void ownBuildCfgString(Runtime::String& value, std::vector<std::unique_ptr<Utf8>>& ownedStrings)
    {
        if (!value.ptr || !value.length)
        {
            value = {};
            return;
        }

        auto owned   = std::make_unique<Utf8>(value);
        value.ptr    = owned->data();
        value.length = owned->size();
        ownedStrings.push_back(std::move(owned));
    }

    void reapplyBuildCfgPresetOverrides(Runtime::BuildCfg& buildCfg, const Runtime::BuildCfg& explicitBuildCfg)
    {
        buildCfg.safetyGuards              = explicitBuildCfg.safetyGuards;
        buildCfg.sanityGuards              = explicitBuildCfg.sanityGuards;
        buildCfg.allocatorCaptureStack     = explicitBuildCfg.allocatorCaptureStack;
        buildCfg.allocatorLeaks            = explicitBuildCfg.allocatorLeaks;
        buildCfg.allocatorTrackAllocations = explicitBuildCfg.allocatorTrackAllocations;
        buildCfg.allocatorElectricMode     = explicitBuildCfg.allocatorElectricMode;
        buildCfg.allocatorFillMemory       = explicitBuildCfg.allocatorFillMemory;
        buildCfg.errorStackTrace           = explicitBuildCfg.errorStackTrace;
        buildCfg.backend.optimLevel        = explicitBuildCfg.backend.optimLevel;
        buildCfg.backend.vectorize         = explicitBuildCfg.backend.vectorize;
        buildCfg.backend.inlineMode        = explicitBuildCfg.backend.inlineMode;
        buildCfg.backend.debugInfo         = explicitBuildCfg.backend.debugInfo;
        buildCfg.backend.math.fma          = explicitBuildCfg.backend.math.fma;
        buildCfg.backend.math.noNaN        = explicitBuildCfg.backend.math.noNaN;
        buildCfg.backend.math.noInf        = explicitBuildCfg.backend.math.noInf;
        buildCfg.backend.math.noSignedZero = explicitBuildCfg.backend.math.noSignedZero;
    }

    void reapplyExplicitBuildCfgOverrides(Runtime::BuildCfg& buildCfg, const CommandLine& cmdLine)
    {
        if (cmdLine.buildCfgExplicit)
            reapplyBuildCfgPresetOverrides(buildCfg, cmdLine.defaultBuildCfg);

        buildCfg.backendKind = effectiveBackendKind(cmdLine, buildCfg.backendKind);
        if (cmdLine.optimLevelExplicit)
            buildCfg.backend.optimLevel = cmdLine.optimLevel;
        if (cmdLine.debugInfo)
            buildCfg.backend.debugInfo = true;

        if (cmdLine.artifactNameExplicit)
            buildCfg.name = cmdLine.defaultBuildCfg.name;
        if (cmdLine.moduleNamespaceExplicit)
            buildCfg.moduleNamespace = cmdLine.defaultBuildCfg.moduleNamespace;
        if (cmdLine.outDirExplicit)
            buildCfg.outDir = cmdLine.defaultBuildCfg.outDir;
        if (cmdLine.workDirExplicit)
            buildCfg.workDir = cmdLine.defaultBuildCfg.workDir;
    }

    // Every string a build configuration carries, in one place: ownership, the setup cache
    // writer and its reader all walk the same list, so a field added here reaches all three.
    template<typename Config, typename Visit>
    void visitBuildCfgStrings(Config& buildCfg, Visit&& visit)
    {
        visit(buildCfg.moduleNamespace);

        visit(buildCfg.warnings.asErrors);
        visit(buildCfg.warnings.asWarnings);
        visit(buildCfg.warnings.disabled);

        visit(buildCfg.name);
        visit(buildCfg.outDir);
        visit(buildCfg.workDir);
        visit(buildCfg.repoPath);

        visit(buildCfg.resAppIcoFileName);
        visit(buildCfg.resAppName);
        visit(buildCfg.resAppDescription);
        visit(buildCfg.resAppCompany);
        visit(buildCfg.resAppCopyright);

        visit(buildCfg.genDoc.outputName);
        visit(buildCfg.genDoc.titleToc);
        visit(buildCfg.genDoc.titleContent);
        visit(buildCfg.genDoc.css);
        visit(buildCfg.genDoc.icon);
        visit(buildCfg.genDoc.morePages);

        visit(buildCfg.genDoc.quoteIconNote);
        visit(buildCfg.genDoc.quoteIconTip);
        visit(buildCfg.genDoc.quoteIconWarning);
        visit(buildCfg.genDoc.quoteIconAttention);
        visit(buildCfg.genDoc.quoteIconExample);

        visit(buildCfg.genDoc.quoteTitleNote);
        visit(buildCfg.genDoc.quoteTitleTip);
        visit(buildCfg.genDoc.quoteTitleWarning);
        visit(buildCfg.genDoc.quoteTitleAttention);
        visit(buildCfg.genDoc.quoteTitleExample);

        visit(buildCfg.genDoc.brandName);
        visit(buildCfg.genDoc.brandUrl);
        visit(buildCfg.genDoc.navLinks);
        visit(buildCfg.genDoc.footer);

        visit(buildCfg.registeredConfigs);
    }

    void ownBuildCfgStrings(Runtime::BuildCfg& buildCfg, std::vector<std::unique_ptr<Utf8>>& ownedStrings)
    {
        std::vector<std::unique_ptr<Utf8>> newOwnedStrings;
        visitBuildCfgStrings(buildCfg, [&newOwnedStrings](Runtime::String& value) { ownBuildCfgString(value, newOwnedStrings); });
        ownedStrings.swap(newOwnedStrings);
    }

    fs::path workspaceModuleDirectory(const fs::path& workspacePath, std::string_view moduleName)
    {
        return (WorkspaceLayout::workspaceModulesDirectory(workspacePath) / fs::path(std::string(moduleName))).lexically_normal();
    }

    fs::path workspaceModuleOutputDirectory(const fs::path& workspacePath, const Utf8& moduleName, const CommandLine& cmdLine, const Runtime::BuildCfgBackendKind backendKind, const bool workDirectory)
    {
        const Runtime::BuildCfgBackendKind effectiveKind = effectiveBackendKind(cmdLine, backendKind);
        const bool                         transientTest = cmdLine.command == CommandKind::Test && effectiveKind != Runtime::BuildCfgBackendKind::Executable;
        fs::path                           result        = workDirectory || transientTest ? WorkspaceLayout::workspaceWorkDirectory(workspacePath) : WorkspaceLayout::workspaceOutputDirectory(workspacePath);
        result /= fs::path(moduleName.c_str());
        if (cmdLine.command == CommandKind::Test)
            result /= "test";
        else
            result /= fs::path(backendKindName(backendKind).c_str());
        result /= fs::path(artifactConfigurationName(cmdLine).c_str());
        result /= fs::path(targetArchName(cmdLine.targetArch).c_str());
        return result.lexically_normal();
    }

    // Answers where the standard library workspace lives.
    //
    // A standard library sitting beside the compiler wins, and `SWAG_PATH` answers only for a
    // compiler installed without one. A compiler and its library are built together and are one
    // thing: `collectFiles` already takes `runtime` from the compiler's own directory
    // unconditionally, so taking `std` from anywhere else pairs one checkout's runtime with
    // another checkout's library. That is what a second working tree hits — `SWAG_PATH` still
    // names the first one — and it fails as an unknown symbol in a library that looks present.
    //
    // It is also what lets a fresh checkout run `tools\setup.bat`, which sets `SWAG_PATH`,
    // before anything has been configured.
    Result resolveSwagStdWorkspaceRoot(fs::path& outRoot, TaskContext& ctx)
    {
        outRoot = FileSystem::standardLibraryWorkspaceRoot(Os::getExeFullName());
        if (outRoot.empty())
            return FileSystem::reportInvalidFolder(ctx, "SWAG_PATH", "environment variable is not defined, and no standard library sits beside the compiler");
        SWC_RESULT(FileSystem::resolveFolder(ctx, outRoot));
        return Result::Continue;
    }

    bool shouldSkipWorkspaceEntry(const fs::directory_entry& entry)
    {
        std::error_code ec;
        if (!entry.is_directory(ec) || ec)
            return true;

        const std::string name = entry.path().filename().string();
        return !name.empty() && name[0] == '.';
    }

    Utf8 formatWorkspaceStageStat(const CompilerInstance::WorkspaceBuildLogState& workspaceLogState)
    {
        std::vector<Utf8> parts;

        if (workspaceLogState.activeModules)
        {
            if (workspaceLogState.builtModules < workspaceLogState.activeModules)
                parts.push_back(ScopedTimedLog::formatStatRatio(workspaceLogState.builtModules, workspaceLogState.activeModules, "module"));
            else
                parts.push_back(ScopedTimedLog::formatStatCount(workspaceLogState.activeModules, "module"));
        }
        else if (workspaceLogState.discoveredModules)
        {
            parts.push_back(ScopedTimedLog::formatStatCount(workspaceLogState.discoveredModules, "module"));
        }

        return ScopedTimedLog::joinStatItems(parts);
    }

    Utf8 formatWorkspaceModuleStageStat(const TaskContext& ctx, const CompilerInstance& compiler, const ScopedTimedLog::StatsSnapshot& deltaSnapshot)
    {
        std::vector<Utf8> parts;
        if (deltaSnapshot.numFiles)
            parts.push_back(ScopedTimedLog::formatStatCount(deltaSnapshot.numFiles, "file"));

        if (ctx.cmdLine().command == CommandKind::Test)
            ScopedTimedLog::appendTestStats(parts, deltaSnapshot.numTests, deltaSnapshot.numTestsFailed);

        const Utf8& artifactLabel = compiler.lastArtifactLabel();
        if (!artifactLabel.empty())
            parts.push_back(Utf8{artifactLabel});

        return ScopedTimedLog::joinStatItems(parts);
    }

    void collectSwagFilesRec(const CommandLine& cmdLine, const fs::path& folder, std::vector<fs::path>& files, const bool canFilter = true)
    {
        std::error_code ec;
        for (fs::recursive_directory_iterator it(folder, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
            {
                ec.clear();
                continue;
            }

            const fs::directory_entry& entry = *it;
            if (!entry.is_regular_file(ec))
            {
                ec.clear();
                continue;
            }

            const fs::path&   path = entry.path();
            const std::string ext  = path.extension().string();
            if (ext != ".swg" && ext != ".swgs")
                continue;

            if (canFilter && !cmdLine.fileFilter.empty())
            {
                const std::string pathString = path.string();
                bool              ignore     = false;
                for (const Utf8& filter : cmdLine.fileFilter)
                {
                    if (!pathString.contains(filter))
                    {
                        ignore = true;
                        break;
                    }
                }

                if (ignore)
                    continue;
            }

            files.push_back(path);
        }
    }

    constexpr std::string_view K_WORKSPACE_ARTIFACT_MANIFEST_FILE    = ".swc-artifacts";
    constexpr std::string_view K_WORKSPACE_ARTIFACT_MANIFEST_VERSION = "version=11";

    struct WorkspaceArtifactManifest
    {
        std::vector<fs::path>                  inputs;
        std::vector<fs::path>                  artifacts;
        Os::FileChangeTime                      inputsReadTime{};
        Utf8                                   configuration;
        Utf8                                   tagsFingerprint;
    };

    Utf8 workspaceFingerprint(const std::string_view contents)
    {
        return Utf8Helper::toLowerHex(sha256(std::as_bytes(std::span{contents})));
    }

    Utf8 workspaceTagsFingerprint(const std::span<const Utf8> tags)
    {
        // Tags can contain typed values and delimiters. Encode lengths and retain command-line
        // order so different lists cannot share an identity or change override precedence.
        Utf8 identity;
        for (const Utf8& tag : tags)
        {
            identity += std::format("{}:", tag.size());
            identity += tag;
        }
        return workspaceFingerprint(identity.view());
    }

    // What a command line changes in a module's code without changing where its artifacts go.
    // The configuration, the artifact kind and the architecture already name the output
    // directory; an artifact built with anything listed here set differently is another program.
    Utf8 workspaceArtifactConfiguration(const CompilerInstance& compiler)
    {
        const Runtime::BuildCfgBackend& backend = compiler.buildCfg().backend;
        const CommandLine& cmdLine = compiler.cmdLine();
        Utf8 configuration = std::format("os:{};debug-info:{};no-runtime-symbols:{};optim-level:{};cpu:{}",
                                         static_cast<int>(cmdLine.targetOs), backend.debugInfo, cmdLine.noRuntimeSymbols,
                                         static_cast<int>(backend.optimLevel), cmdLine.targetCpu.view());
        const auto appendValues = [&configuration](std::string_view label, const auto& values) {
            for (const Utf8& value : values)
                configuration += std::format(";{}={}:{}", label, value.size(), value.view());
        };
        appendValues("file-filter", cmdLine.fileFilter);
        appendValues("warn-as-error", cmdLine.warnAsErrors);
        appendValues("warn-as-warning", cmdLine.warnAsWarnings);
        appendValues("warn-disable", cmdLine.warnDisabled);
        return configuration;
    }

    // Each build mode keeps its own manifest, so alternating `test` and `run` does
    // not make each one look stale to the other and force a rebuild every time.
    fs::path workspaceArtifactManifestPath(const fs::path& outDir, const CommandLine& cmdLine)
    {
        return (outDir / std::format("{}{}", K_WORKSPACE_ARTIFACT_MANIFEST_FILE, artifactModeSuffix(cmdLine))).lexically_normal();
    }

    bool workspacePathIsArtifactManifest(const fs::path& path)
    {
        return path.filename().string().starts_with(K_WORKSPACE_ARTIFACT_MANIFEST_FILE);
    }

    void normalizeWorkspacePathsLexically(std::vector<fs::path>& paths)
    {
        for (fs::path& path : paths)
            path = path.lexically_normal();

        std::ranges::sort(paths, {}, &fs::path::native);
        paths.erase(std::ranges::unique(paths).begin(), paths.end());
    }

    bool workspacePathListContainsAll(std::span<const fs::path> paths, std::span<const fs::path> expectedPaths)
    {
        return std::ranges::includes(paths, expectedPaths, {}, &fs::path::native, &fs::path::native);
    }

    bool tryCollectLatestWorkspaceTreeChangeTime(Os::FileChangeTime& outTime, const fs::path& root)
    {
        if (!Os::tryGetFileChangeTime(outTime, root))
            return false;

        std::error_code ec;
        for (fs::recursive_directory_iterator it(root, fs::directory_options::none, ec), end; !ec && it != end; it.increment(ec))
        {
            Os::FileChangeTime entryTime;
            if (!Os::tryGetFileChangeTime(entryTime, it->path()))
                return false;
            if (entryTime > outTime)
                outTime = entryTime;
        }

        return !ec;
    }

    // Dates the compiler that is about to consume a build.
    //
    // The embedded runtime sources (<resource root>/runtime/*.swg) are compiled into every
    // module, so a change there must invalidate a build exactly like a new compiler binary.
    bool tryGetCompilerBuildTime(Os::FileChangeTime& outTime, const fs::path& compilerPath)
    {
        if (!Os::tryGetFileChangeTime(outTime, compilerPath))
            return false;

        Os::FileChangeTime runtimeTime{};
        if (!tryCollectLatestWorkspaceTreeChangeTime(runtimeTime, FileSystem::compilerResourceRoot(compilerPath) / "runtime"))
            return false;

        outTime = std::max(outTime, runtimeTime);
        return true;
    }

    // ------------------------------------------------------------------ module setup cache
    //
    // Running a module's setup means parsing and sema'ing its module.swg on top of the whole
    // runtime prelude, and running its build-configuration block on the JIT. Compatible
    // commands reuse this snapshot from the shared compiler cache.
    //
    // The snapshot is a byte image: the build configuration is copied as it lies, and every
    // string it carries is written after it, in the order visitBuildCfgStrings walks them. The
    // reader restores each string into storage the snapshot owns, exactly as ownBuildCfgStrings
    // does after a live setup. A compiler of another build never reads it, because the compiler's
    // identity is part of the fingerprint.
    constexpr uint32_t K_MODULE_SETUP_CACHE_MAGIC = 0x52555357; // Source setup format with input checksums
    constexpr size_t   K_MODULE_SETUP_CHECKSUM_SIZE = 32;

    struct ModuleSetupCacheWriter
    {
        ByteArray bytes;

        void u32(const uint32_t value) { bytes.appendLe32(value); }

        void blob(const void* data, const size_t size)
        {
            u32(static_cast<uint32_t>(size));
            bytes.append(std::span(static_cast<const std::byte*>(data), size));
        }

        void str(const std::string_view value)
        {
            blob(value.data(), value.size());
        }

        void path(const fs::path& value)
        {
            str(Utf8(value).view());
        }
    };

    struct ModuleSetupCacheReader
    {
        ByteView              bytes;
        size_t                offset = 0;
        bool                  failed = false;

        bool has(const size_t size)
        {
            if (failed || size > bytes.size() - offset)
                failed = true;
            return !failed;
        }

        uint32_t u32()
        {
            if (!has(sizeof(uint32_t)))
                return 0;
            const uint32_t value = bytes.readLe32(offset);
            offset += sizeof(value);
            return value;
        }

        std::string_view str()
        {
            const uint32_t size = u32();
            if (!has(size))
                return {};
            const std::string_view value(reinterpret_cast<const char*>(bytes.data() + offset), size);
            offset += size;
            return value;
        }

        fs::path path()
        {
            return fs::path(Utf8(str()).c_str());
        }
    };

    bool moduleSetupInputMatches(ModuleSetupCacheReader& reader, fs::path& outPath)
    {
        outPath                         = reader.path();
        const std::string_view checksum = reader.str();
        if (reader.failed || checksum.size() != K_MODULE_SETUP_CHECKSUM_SIZE)
            return false;

        ByteArray               contents;
        FileSystem::IoErrorInfo ioError;
        if (FileSystem::readBinaryFile(outPath, contents, ioError) != Result::Continue)
            return false;

        const auto current = sha256(contents.span());
        return std::memcmp(current.data(), checksum.data(), current.size()) == 0;
    }

    // Everything a setup can observe that is not a file: the compiler that runs it, and the
    // command line as the build-configuration block sees it through the compiler API. Anything
    // else influencing a setup must be registered as a compiler input.
    Utf8 moduleSetupCacheKey(const CommandLine& cmdLine, const fs::path& moduleFile, const fs::path& compilerPath)
    {
        // The prelude can change independently of the installed compiler. Every setup
        // in this process uses that same runtime tree.
        static const Utf8 preludeIdentity = [&] -> Utf8 {
            const fs::path runtime = FileSystem::compilerResourceRoot(compilerPath) / "runtime";
            Os::FileChangeTime time{};
            if (!tryCollectLatestWorkspaceTreeChangeTime(time, runtime))
                return {};
            return std::format("{}:{}", Utf8Helper::normalizePathForCompare(runtime).view(), time.time_since_epoch().count());
        }();
        if (compilerCacheIdentity().empty() || preludeIdentity.empty())
            return {};

        ModuleSetupCacheWriter identity;
        identity.str("module setup");
        identity.u32(K_MODULE_SETUP_CACHE_MAGIC);
        identity.str(preludeIdentity.view());
        identity.str(Utf8Helper::normalizePathForCompare(moduleFile).view());
        identity.u32(static_cast<uint32_t>(cmdLine.command));
        identity.u32(static_cast<uint32_t>(cmdLine.targetOs));
        identity.u32(static_cast<uint32_t>(cmdLine.targetArch));
        identity.u32(static_cast<uint32_t>(cmdLine.backendKind));
        identity.u32(static_cast<uint32_t>(cmdLine.optimLevel));
        for (const bool flag : {cmdLine.optimLevelExplicit, cmdLine.debugInfo, cmdLine.scriptMode, cmdLine.sourceDrivenTest,
                                cmdLine.buildCfgExplicit, cmdLine.artifactKindExplicit, cmdLine.artifactNameExplicit,
                                cmdLine.moduleNamespaceExplicit, cmdLine.outDirExplicit, cmdLine.workDirExplicit, cmdLine.output})
            identity.u32(flag);
        for (const auto* value : {&cmdLine.targetCpu, &cmdLine.buildCfg, &cmdLine.name, &cmdLine.moduleNamespace,
                                  &cmdLine.outDirStorage, &cmdLine.workDirStorage, &cmdLine.docCss})
            identity.str(value->view());
        identity.path(cmdLine.docOutputDir);
        identity.str(workspaceTagsFingerprint(cmdLine.tags).view());
        for (const auto* warnings : {&cmdLine.warnAsErrors, &cmdLine.warnAsWarnings, &cmdLine.warnDisabled})
        {
            identity.u32(static_cast<uint32_t>(warnings->size()));
            for (const Utf8& warning : *warnings)
                identity.str(warning.view());
        }
        return Utf8Helper::toLowerHex(sha256(identity.bytes.span()));
    }

    void writeModuleSetupCache(const Utf8& key, const fs::path& moduleFile, const auto& snapshot)
    {
        static_assert(std::is_trivially_copyable_v<Runtime::BuildCfg>);

        ModuleSetupCacheWriter writer;
        writer.u32(K_MODULE_SETUP_CACHE_MAGIC);

        // Publish the checksums of the bytes the setup used. Reading the files at publication
        // could cache the old build configuration under an edit that arrived during setup.
        const auto& checksums = snapshot.inputChecksums;
        const auto  module    = checksums.find(FileSystem::normalizePath(moduleFile));
        if (module == checksums.end())
            return;
        const auto hasChecksum = [&checksums](const fs::path& path) { return checksums.contains(FileSystem::normalizePath(path)); };
        if (!std::ranges::all_of(snapshot.loadedFiles, hasChecksum) || !std::ranges::all_of(snapshot.compilerInputFiles, hasChecksum))
            return;

        writer.u32(static_cast<uint32_t>(checksums.size()));
        writer.path(module->first);
        writer.blob(module->second.data(), module->second.size());
        for (const auto& [path, checksum] : checksums)
        {
            if (path == module->first)
                continue;
            writer.path(path);
            writer.blob(checksum.data(), checksum.size());
        }

        writer.u32(static_cast<uint32_t>(snapshot.imports.size()));
        for (const CompilerInstance::ModuleSetupImport& importRequest : snapshot.imports)
        {
            writer.str(importRequest.moduleName.view());
            writer.str(importRequest.location.view());
            writer.path(importRequest.baseDir);
        }

        writer.u32(static_cast<uint32_t>(snapshot.loadedFiles.size()));
        for (const fs::path& path : snapshot.loadedFiles)
            writer.path(path);
        writer.u32(static_cast<uint32_t>(snapshot.compilerInputFiles.size()));
        for (const fs::path& path : snapshot.compilerInputFiles)
            writer.path(path);

        Runtime::BuildCfg image = snapshot.buildCfg;
        visitBuildCfgStrings(image, [](Runtime::String& value) { value = {}; });
        writer.blob(&image, sizeof(image));
        Runtime::BuildCfg buildCfg = snapshot.buildCfg;
        visitBuildCfgStrings(buildCfg, [&writer](const Runtime::String& value) {
            writer.str(value.ptr && value.length ? std::string_view(value.ptr, value.length) : std::string_view{});
        });

        const auto checksum = sha256Parts({writer.bytes.span(), std::as_bytes(std::span(key.data(), key.size()))});
        writer.bytes.append(std::as_bytes(std::span(checksum)));
        CompilerCacheStore::get().write(key, std::move(writer.bytes));
    }

    bool readModuleSetupCache(auto& out, const Utf8& key, const fs::path& moduleFile)
    {
        const auto record = CompilerCacheStore::get().read(key);
        constexpr size_t checksumSize = K_MODULE_SETUP_CHECKSUM_SIZE;
        if (!record || record.bytes.size() <= checksumSize)
            return false;

        const auto payload  = record.bytes.span().first(record.bytes.size() - checksumSize);
        const auto checksum = sha256Parts({payload, std::as_bytes(std::span(key.data(), key.size()))});
        if (std::memcmp(checksum.data(), record.bytes.data() + payload.size(), checksumSize))
            return false;

        ModuleSetupCacheReader reader{.bytes = ByteView(payload)};
        if (reader.u32() != K_MODULE_SETUP_CACHE_MAGIC)
            return false;

        const uint32_t inputCount = reader.u32();
        if (!inputCount)
            return false;
        for (uint32_t i = 0; i < inputCount; ++i)
        {
            fs::path inputPath;
            if (!moduleSetupInputMatches(reader, inputPath))
                return false;
            if (i == 0 && !FileSystem::pathEquals(inputPath, moduleFile))
                return false;
        }

        const uint32_t importCount = reader.u32();
        if (reader.failed || importCount > (payload.size() - reader.offset) / (3 * sizeof(uint32_t)))
            return false;
        out.imports.reserve(importCount);
        for (uint32_t i = 0; i < importCount; ++i)
        {
            CompilerInstance::ModuleSetupImport importRequest;
            importRequest.moduleName      = Utf8(reader.str());
            importRequest.location        = Utf8(reader.str());
            importRequest.baseDir         = reader.path();
            if (reader.failed)
                return false;
            out.imports.push_back(std::move(importRequest));
        }

        const uint32_t loadedCount = reader.u32();
        for (uint32_t i = 0; i < loadedCount && !reader.failed; ++i)
            out.loadedFiles.insert(reader.path());
        const uint32_t compilerInputCount = reader.u32();
        for (uint32_t i = 0; i < compilerInputCount && !reader.failed; ++i)
            out.compilerInputFiles.insert(reader.path());

        const std::string_view image = reader.str();
        if (reader.failed || image.size() != sizeof(Runtime::BuildCfg))
            return false;
        std::memcpy(&out.buildCfg, image.data(), sizeof(Runtime::BuildCfg));

        visitBuildCfgStrings(out.buildCfg, [&reader, &out](Runtime::String& value) {
            value                         = {};
            const std::string_view stored = reader.str();
            if (stored.empty())
                return;
            auto owned   = std::make_unique<Utf8>(stored);
            value.ptr    = owned->data();
            value.length = owned->size();
            out.ownedStrings.push_back(std::move(owned));
        });
        return !reader.failed && reader.offset == payload.size();
    }

    void appendWorkspaceInputFiles(std::vector<fs::path>& outInputs, const std::set<fs::path>& inputFiles)
    {
        outInputs.reserve(outInputs.size() + inputFiles.size());
        for (const fs::path& filePath : inputFiles)
            outInputs.push_back(filePath);
    }

    bool isDisabledInProductionBuild(const fs::path& path)
    {
        // This is a conservative cache proof, not a file-name rule. Recheck the guard on
        // every probe so changing or removing it immediately invalidates the artifact.
        bool underTests = false;
        for (const fs::path& component : path.parent_path())
            underTests |= component == "tests";
        if (!underTests)
            return false;

        std::ifstream input(path, std::ios::binary);
        std::string   line;
        if (!std::getline(input, line))
            return false;
        if (line.ends_with('\r'))
            line.pop_back();
        if (line != "#global if #command == Swag.CompilerCommand.Test")
            return false;

        // A later #global condition could re-enable declarations in this file. Accept only
        // visibility directives after the guard; unknown forms remain ordinary inputs.
        while (std::getline(input, line))
        {
            const size_t directive = line.find("#global");
            if (directive == std::string::npos)
                continue;
            if (line.ends_with('\r'))
                line.pop_back();
            const std::string_view tail(line.data() + directive, line.size() - directive);
            if (tail != "#global private" && tail != "#global public")
                return false;
        }
        return input.eof();
    }

    void collectWorkspaceModuleInputs(std::vector<fs::path>& outInputs, const CommandLine& cmdLine, const fs::path& moduleFile, const fs::path& sourceDir, const std::set<fs::path>& loadedFiles, const std::set<fs::path>& setupCompilerInputFiles, const std::set<fs::path>& buildCompilerInputFiles)
    {
        outInputs.clear();
        if (!moduleFile.empty())
            outInputs.push_back(moduleFile);

        if (!sourceDir.empty())
        {
            const size_t sourceInputStart = outInputs.size();
            collectSwagFilesRec(cmdLine, sourceDir, outInputs, true);
            if (cmdLine.command == CommandKind::Build && !cmdLine.sourceDrivenTest)
                outInputs.erase(std::remove_if(outInputs.begin() + sourceInputStart, outInputs.end(), isDisabledInProductionBuild), outInputs.end());
        }

        appendWorkspaceInputFiles(outInputs, loadedFiles);
        appendWorkspaceInputFiles(outInputs, setupCompilerInputFiles);
        appendWorkspaceInputFiles(outInputs, buildCompilerInputFiles);

        // Every path here is already canonical: the module directory was normalized when the
        // workspace was scanned, the enumeration below it yields on-disk names, and a loaded or
        // registered file was normalized when it was registered. Resolving each one again on
        // disk was a third of a no-op build.
        normalizeWorkspacePathsLexically(outInputs);
    }

    void collectWorkspaceOutputArtifacts(std::vector<fs::path>& outArtifacts, const fs::path& outDir)
    {
        outArtifacts.clear();
        if (outDir.empty())
            return;

        std::error_code ec;
        for (fs::recursive_directory_iterator it(outDir, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                return;

            ec.clear();
            if (!it->is_regular_file(ec) || ec)
                continue;

            const fs::path normalizedPath = FileSystem::normalizePath(it->path());

            // Other manifests and a competing publisher's staging files are not artifacts:
            // replacing or removing them must not invalidate this completed build.
            if (workspacePathIsArtifactManifest(normalizedPath) || FileSystem::isMovedAsidePath(normalizedPath))
                continue;

            fs::path relativePath = normalizedPath.lexically_relative(outDir);
            if (relativePath.empty())
                relativePath = normalizedPath.filename();
            outArtifacts.push_back(relativePath.lexically_normal());
        }

        normalizeWorkspacePathsLexically(outArtifacts);
    }

    bool readWorkspaceArtifactManifest(WorkspaceArtifactManifest& out, const fs::path& path)
    {
        std::ifstream file(path, std::ios::binary);
        std::string   line;
        std::string   fingerprint;
        if (!std::getline(file, line) || line != K_WORKSPACE_ARTIFACT_MANIFEST_VERSION || !std::getline(file, fingerprint))
            return false;

        // A damaged list can still parse after losing a dynamically discovered input.
        std::string contents{std::istreambuf_iterator<char>{file}, std::istreambuf_iterator<char>{}};
        if (workspaceFingerprint(contents) != fingerprint)
            return false;

        std::istringstream in(std::move(contents));
        if (!std::getline(in, static_cast<std::string&>(out.configuration)) || !std::getline(in, static_cast<std::string&>(out.tagsFingerprint)) || !std::getline(in, line))
            return false;

        Os::FileChangeTime::duration::rep ticks{};
        const auto [end, ec] = std::from_chars(line.data(), line.data() + line.size(), ticks);
        if (ec != std::errc{} || end != line.data() + line.size() || !std::getline(in, line) || line != "[inputs]")
            return false;
        out.inputsReadTime = Os::FileChangeTime{Os::FileChangeTime::duration{ticks}};

        bool readingInputs = true;
        while (std::getline(in, line))
        {
            if (readingInputs && line == "[artifacts]")
            {
                readingInputs = false;
                continue;
            }
            fs::path entry(line);
            if (entry.empty() || readingInputs != entry.is_absolute())
                return false;
            if (!readingInputs && std::ranges::find(entry, fs::path("..")) != entry.end())
                return false;
            (readingInputs ? out.inputs : out.artifacts).push_back(std::move(entry));
        }
        normalizeWorkspacePathsLexically(out.inputs);
        normalizeWorkspacePathsLexically(out.artifacts);
        return in.eof() && !readingInputs && !out.artifacts.empty();
    }

    Result writeWorkspaceArtifactManifest(TaskContext& ctx, const WorkspaceArtifactManifest& manifest, const fs::path& path)
    {
        Utf8 content = std::format("{}\n{}\n{}\n[inputs]\n", manifest.configuration.view(), manifest.tagsFingerprint.view(), manifest.inputsReadTime.time_since_epoch().count());
        for (const fs::path& entry : manifest.inputs)
            content += std::format("{}\n", Utf8(entry).view());
        content += "[artifacts]\n";
        for (const fs::path& entry : manifest.artifacts)
            content += std::format("{}\n", Utf8(entry).view());

        const Utf8 fingerprint = workspaceFingerprint(content.view());
        content.insert(0, std::format("{}\n{}\n", K_WORKSPACE_ARTIFACT_MANIFEST_VERSION, fingerprint.view()));

        FileSystem::IoErrorInfo error;
        if (FileSystem::writeBinaryFileAtomic(path, content.data(), content.size(), error) != Result::Continue)
            return FileSystem::reportPathError(ctx, DiagnosticId::cmd_err_workspace_manifest_write_failed, path, FileSystem::describeIoFailure(error));
        return Result::Continue;
    }

    bool workspaceManifestContainsArtifact(const WorkspaceArtifactManifest& manifest, const fs::path& outDir, const fs::path& artifactPath)
    {
        const fs::path normalizedArtifactPath = FileSystem::normalizePath(artifactPath);
        for (const fs::path& relativePath : manifest.artifacts)
        {
            if (FileSystem::pathEquals(FileSystem::normalizePath(outDir / relativePath), normalizedArtifactPath))
                return true;
        }

        return false;
    }

    enum class WorkspaceArtifactState : uint8_t
    {
        Stale,
        UpToDate,
    };

    // Treat changes in the same clock tick as the start of the build as stale as well.
    bool workspaceInputsAreCurrent(const WorkspaceArtifactManifest& manifest, const fs::path& compilerPath, const std::span<const fs::path> currentInputs)
    {
        if (!workspacePathListContainsAll(manifest.inputs, currentInputs))
            return false;

        Os::FileChangeTime compilerTime;
        if (!tryGetCompilerBuildTime(compilerTime, compilerPath) || manifest.inputsReadTime <= compilerTime)
            return false;
        for (const fs::path& path : manifest.inputs)
        {
            Os::FileChangeTime pathTime;
            if (!Os::tryGetFileChangeTime(pathTime, path) || manifest.inputsReadTime <= pathTime)
                return false;
        }
        return true;
    }

    WorkspaceArtifactState workspaceArtifactState(const WorkspaceArtifactManifest& manifest, const fs::path& outDir, const fs::path& manifestPath, const fs::path& compilerPath, std::span<const fs::path> inputs, std::span<const fs::path> requiredArtifacts, std::string_view configuration, std::span<const Utf8> tags)
    {
        if (manifest.configuration != configuration || manifest.tagsFingerprint != workspaceTagsFingerprint(tags) ||
            !workspaceInputsAreCurrent(manifest, compilerPath, inputs))
            return WorkspaceArtifactState::Stale;

        Os::FileChangeTime manifestTime;
        if (!Os::tryGetFileChangeTime(manifestTime, manifestPath) || manifest.inputsReadTime > manifestTime)
            return WorkspaceArtifactState::Stale;

        std::error_code error;
        for (const fs::path& artifact : manifest.artifacts)
        {
            if (!std::filesystem::is_regular_file(outDir / artifact, error))
                return WorkspaceArtifactState::Stale;
        }
        for (const fs::path& artifact : requiredArtifacts)
        {
            if (!workspaceManifestContainsArtifact(manifest, outDir, artifact))
                return WorkspaceArtifactState::Stale;
        }
        return WorkspaceArtifactState::UpToDate;
    }

    bool shouldTryReuseWorkspaceArtifacts(const CommandLine& cmdLine, const Runtime::BuildCfgBackendKind backendKind)
    {
        if (effectiveBackendKind(cmdLine, backendKind) != Runtime::BuildCfgBackendKind::Executable)
            return false;
        if (cmdLine.rebuild || cmdLine.dryRun || cmdLine.showConfig)
            return false;

        if (cmdLine.command == CommandKind::Test)
            return !cmdLine.testJit && cmdLine.testNative && cmdLine.output;

        return cmdLine.command == CommandKind::Build || isRunLikeCommand(cmdLine.command);
    }

    bool hasWorkspaceVerifyDirectives(const CompilerInstance& compiler)
    {
        for (const SourceFile* file : compiler.files())
        {
            if (file && file->unitTest().hasExpectedDirectives())
                return true;
        }

        return false;
    }

    bool shouldWriteWorkspaceArtifactManifest(const CompilerInstance& compiler)
    {
        const CommandLine& cmdLine = compiler.cmdLine();
        if (cmdLine.dryRun || cmdLine.showConfig || compiler.jitHasUntrackedEffects() || compiler.buildCfg().backendKind != Runtime::BuildCfgBackendKind::Executable)
            return false;
        if (cmdLine.command != CommandKind::Test)
            return cmdLine.command == CommandKind::Build || isRunLikeCommand(cmdLine.command);

        // A cached test has no AST against which source-driven expectations can be checked.
        // Keep compiling those inputs so every Verify directive is evaluated on every run.
        return compiler.nativeArtifactBuilt() && !hasWorkspaceVerifyDirectives(compiler);
    }

    Utf8 formatWorkspaceArtifactStat(const CompilerInstance& compiler, const std::string_view state = {})
    {
        std::vector<Utf8> parts;
        parts.push_back(Utf8{state});
        if (!compiler.lastArtifactLabel().empty())
            parts.push_back(Utf8{compiler.lastArtifactLabel()});
        return ScopedTimedLog::joinStatItems(parts);
    }

}

static bool tryCaptureLiteralModuleImports(const fs::path& depsFile, std::vector<CompilerInstance::ModuleSetupImport>& outImports)
{
    std::string             content;
    FileSystem::IoErrorInfo ioError;
    if (FileSystem::readTextFile(depsFile, content, ioError) != Result::Continue)
        return false;

    const auto skipSpaces = [](const std::string_view line, size_t& pos) {
        while (pos < line.size() && (line[pos] == ' ' || line[pos] == '\t'))
            pos++;
    };
    const auto readQuoted = [](Utf8& outValue, const std::string_view line, size_t& pos) {
        if (pos >= line.size() || line[pos] != '"')
            return false;
        const size_t end = line.find('"', ++pos);
        if (end == std::string_view::npos)
            return false;
        outValue = line.substr(pos, end - pos);
        pos      = end + 1;
        return true;
    };

    size_t contentPos = 0;
    while (contentPos < content.size())
    {
        const size_t                        lineEnd = content.find('\n', contentPos);
        std::string_view                    line{content.data() + contentPos, (lineEnd == std::string::npos ? content.size() : lineEnd) - contentPos};
        CompilerInstance::ModuleSetupImport importRequest;
        contentPos = lineEnd == std::string::npos ? content.size() : lineEnd + 1;
        if (!line.empty() && line.back() == '\r')
            line.remove_suffix(1);

        size_t pos = 0;
        skipSpaces(line, pos);
        constexpr std::string_view prefix = "#import(";
        if (!line.substr(pos).starts_with(prefix))
            return false;

        pos += prefix.size();
        if (!readQuoted(importRequest.moduleName, line, pos))
            return false;

        while (true)
        {
            skipSpaces(line, pos);
            if (pos < line.size() && line[pos] == ')')
            {
                pos++;
                break;
            }
            if (pos >= line.size() || line[pos++] != ',')
                return false;

            skipSpaces(line, pos);

            if (!importRequest.location.empty() || !line.substr(pos).starts_with("location:"))
                return false;
            pos += 9;
            skipSpaces(line, pos);
            if (!readQuoted(importRequest.location, line, pos) || importRequest.location.empty())
                return false;
        }

        skipSpaces(line, pos);
        if (pos != line.size() || importRequest.moduleName.empty())
            return false;

        importRequest.baseDir = depsFile.parent_path();
        outImports.push_back(std::move(importRequest));
    }

    return true;
}

// Source dependencies stay in their original directories. The completed DFS is also the
// order used for initialization and for compiler-generated declarations.
Result CompilerInstance::prepareSourceDependencies(TaskContext& ctx, std::unique_ptr<SourceDependencyPlan>& outPlan, const fs::path& rootModule, const ModuleSetupSnapshot& setup) const
{
    using Kind = Runtime::BuildCfgBackendKind;
    outPlan.reset();
    if (setup.imports.empty())
        return Result::Continue;

    auto                   plan = std::make_unique<SourceDependencyPlan>();
    std::map<Utf8, uint32_t> visited;
    std::map<Utf8, fs::path> namespaces;
    fs::path               stdWorkspace;

    const auto visit = [&](auto&& self, const ModuleSetupImport& request, uint32_t& outOwner) -> Result {
        fs::path moduleDir;
        if (request.location == "swag@std")
        {
            if (stdWorkspace.empty())
                SWC_RESULT(resolveSwagStdWorkspaceRoot(stdWorkspace, ctx));
            moduleDir = workspaceModuleDirectory(stdWorkspace, request.moduleName.view());
        }
        else if (request.location.empty())
        {
            moduleDir = request.baseDir.parent_path() / fs::path(request.moduleName.c_str());
        }
        else
        {
            const fs::path workspace = request.baseDir / fs::path(request.location.c_str());
            moduleDir = workspaceModuleDirectory(workspace, request.moduleName.view());
        }

        fs::path moduleFile = moduleDir / "module.swg";
        SWC_RESULT(FileSystem::resolveFile(ctx, moduleFile));
        moduleDir  = moduleFile.parent_path();
        auto [entry, inserted] = visited.try_emplace(Utf8Helper::normalizePathForCompare(moduleFile), 0);
        if (!inserted)
        {
            if (entry->second)
            {
                outOwner = entry->second;
                return Result::Continue;
            }
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_dependency_cycle);
            diag.addArgument(Diagnostic::ARG_SYM, request.moduleName);
            diag.report(ctx);
            return Result::Error;
        }

        fs::path sourceDir = moduleDir / "src";
        Utf8 because;
        if (FileSystem::resolveExistingFolder(sourceDir, because) != Result::Continue)
            return FileSystem::reportPathError(ctx, DiagnosticId::cmd_err_workspace_module_src_missing, moduleDir);

        CommandLine dep = cmdLine();
        dep.command = CommandKind::Build;
        dep.workspacePath.clear();
        dep.moduleFilePath = moduleFile;
        dep.modulePath = moduleDir;
        dep.name.clear();
        dep.artifactNameExplicit = false;
        dep.moduleNamespace.clear();
        dep.moduleNamespaceExplicit = false;
        dep.backendKind = Kind::None;
        dep.artifactKindExplicit = false;
        dep.outDir.clear();
        dep.workDir.clear();
        dep.outDirStorage.clear();
        dep.workDirStorage.clear();
        dep.outDirExplicit = false;
        dep.workDirExplicit = false;
        dep.directories.clear();
        dep.files.clear();
        dep.fileFilter.clear();
        dep.scriptMode = false;
        dep.sourceDrivenTest = false;
        CommandLineParser::refreshBuildCfg(dep);

        ModuleSetupSnapshot snapshot;
        SWC_RESULT(resolveModuleSetupSnapshot(ctx, dep, moduleFile, snapshot));
        if (snapshot.buildCfg.ignoreInWorkspace)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_ignored_dependency);
            diag.addArgument(Diagnostic::ARG_SYM, Utf8(request.baseDir.filename()));
            diag.addArgument(Diagnostic::ARG_TARGET, request.moduleName);
            diag.report(ctx);
            return Result::Error;
        }
        if (snapshot.buildCfg.backendKind == Kind::Executable)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_source_dependency_executable);
            diag.addArgument(Diagnostic::ARG_SYM, request.moduleName);
            diag.report(ctx);
            return Result::Error;
        }

        Utf8 namespaceName = buildCfgString(snapshot.buildCfg.moduleNamespace);
        if (namespaceName.empty())
        {
            const Utf8 artifactName = buildCfgString(snapshot.buildCfg.name);
            namespaceName = defaultModuleNamespace(artifactName.empty() ? defaultArtifactName(dep) : artifactName);
        }

        const auto [namespaceEntry, namespaceInserted] = namespaces.try_emplace(namespaceName, moduleFile);
        if (!namespaceInserted)
        {
            const Utf8 previousFile = FileSystem::formatFileName(namespaceEntry->second);
            const Utf8 because = std::format("source group namespace '{}' is already declared by '{}'", namespaceName.view(), previousFile.view());
            return FileSystem::reportInvalidFolder(ctx, moduleDir, because);
        }

        std::set<uint32_t> visibleOwners;
        for (const ModuleSetupImport& nested : snapshot.imports)
        {
            uint32_t owner = 0;
            SWC_RESULT(self(self, nested, owner));

            visibleOwners.insert(owner);
            const auto& transitive = plan->dependencies[owner - 1].visibleOwners;
            visibleOwners.insert(transitive.begin(), transitive.end());
        }

        SourceDependency& group = plan->dependencies.emplace_back();
        group.namespaceName    = std::move(namespaceName);
        group.loadedFiles       = std::move(snapshot.loadedFiles);
        group.visibleOwners.assign(visibleOwners.begin(), visibleOwners.end());
        collectSwagFilesRec(dep, sourceDir, group.files, false);
        std::ranges::sort(group.files);
        plan->inputs.push_back(moduleFile);
        plan->inputs.insert(plan->inputs.end(), group.files.begin(), group.files.end());
        appendWorkspaceInputFiles(plan->inputs, group.loadedFiles);
        appendWorkspaceInputFiles(plan->inputs, snapshot.compilerInputFiles);

        outOwner      = static_cast<uint32_t>(plan->dependencies.size());
        entry->second = outOwner;
        return Result::Continue;
    };

    visited.emplace(Utf8Helper::normalizePathForCompare(rootModule), 0);
    for (const ModuleSetupImport& request : setup.imports)
    {
        uint32_t owner = 0;
        SWC_RESULT(visit(visit, request, owner));
    }

    normalizeWorkspacePathsLexically(plan->inputs);
    outPlan = std::move(plan);
    return Result::Continue;
}

void CompilerInstance::applySourceDependencies(const ModuleSetupSnapshot& setup)
{
    moduleSetupImports_     = setup.imports;
    moduleSetupLoadedFiles_ = setup.loadedFiles;

    for (const fs::path& path : setup.loadedFiles)
    {
        const auto existing = std::ranges::find(files_, path, [](const auto& file) -> const fs::path& { return file->path(); });
        if (existing != files_.end())
            (*existing)->addFlag(FileFlagsE::SetupLoaded);
        else
            addResolvedFile(path, FileFlagsE::ModuleSrc | FileFlagsE::SetupLoaded);
    }

    uint32_t owner = 0;
    if (!sourceDependencyPlan_)
        return;

    for (const SourceDependency& dep : sourceDependencyPlan_->dependencies)
    {
        ++owner;
        // A file named by two descriptors is evaluated in each group's own scope.
        for (const fs::path& path : dep.loadedFiles)
            addResolvedFile(path, FileFlagsE::ModuleSrc | FileFlagsE::SetupLoaded).setSourceOwner(owner);
        for (const fs::path& path : dep.files)
        {
            if (dep.loadedFiles.empty() || !dep.loadedFiles.contains(FileSystem::normalizePath(path)))
                addResolvedFile(path, FileFlagsE::ModuleSrc).setSourceOwner(owner);
        }
    }
}

bool CompilerInstance::canSeeSourceOwner(const uint32_t from, const uint32_t owner) const
{
    if (!from || from == owner)
        return true;
    const auto& visible = sourceDependencyPlan_->dependencies[from - 1].visibleOwners;
    return std::ranges::binary_search(visible, owner);
}

void CompilerInstance::assignSourceNamespaces(TaskContext& ctx, const std::span<SourceFile* const> files)
{
    std::vector<SymbolNamespace*> namespaces{moduleNamespace()};
    if (sourceDependencyPlan_)
    {
        constexpr SymbolFlags flags = SymbolFlagsE::Declared | SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted;
        for (const SourceDependency& dep : sourceDependencyPlan_->dependencies)
        {
            const IdentifierRef idRef = ctx.idMgr().addIdentifierOwned(dep.namespaceName, Math::hash(dep.namespaceName));
            auto* ns = Symbol::make<SymbolNamespace>(ctx, nullptr, TokenRef::invalid(), idRef, flags);
            importRootNamespace()->addSingleSymbol(ctx, ns);
            namespaces.push_back(ns);
        }
    }

    for (SourceFile* file : files)
        file->setModuleNamespace(*namespaces[file->sourceOwner()]);
}

// A module's native link, run as a normal job on the shared JobManager. The owned CommandLine,
// CompilerInstance and NativeBackendBuilder must stay alive until the link job is joined and finished:
// the compiler is referenced (by pointer) by the builder, and the CommandLine is referenced (by
// pointer) by the compiler. Declaration order matters for teardown: the job is drained first, then
// the builder, then the compiler, then the CommandLine.
//
// The link runs on its own job client so the next module's (CPU-bound) compilation, which waits only
// on its own client, can overlap it instead of stalling. The job object is owned here so it outlives
// its execution and is torn down with the rest of the retained module state.
struct WorkspaceModuleLink
{
    Utf8                                  moduleName;
    std::unique_ptr<CommandLine>          cmdLine;
    std::unique_ptr<CompilerInstance>     compiler;
    std::unique_ptr<NativeBackendBuilder> builder;
    bool                                  writeManifest = false;
    size_t                                warningsBefore = 0;
    WorkspaceArtifactManifest             manifest;
    fs::path                              manifestPath;
    fs::path                              outDir;
    std::unique_ptr<NativeLinkJob>        linkJob;
    JobClientId                           linkClientId = 0;
    bool                                  linkInFlight = false;

    // Enqueue the prepared link on the shared JobManager under a fresh client, then return so the
    // caller can move on to the next module while a worker thread runs the link.
    void launchLink()
    {
        JobManager& jobMgr = builder->ctx().global().jobMgr();
        linkClientId       = jobMgr.newClientId();
        linkJob            = std::make_unique<NativeLinkJob>(builder->ctx(), builder->deferredToolRun());
        linkInFlight       = true;
        jobMgr.enqueue(*linkJob, JobPriority::Normal, linkClientId);
    }

    // Block until the link job has run to completion (a no-op if it was never launched or already
    // joined). Required before the retained builder/compiler/cmdLine the job references are destroyed.
    void joinLink()
    {
        if (!linkInFlight)
            return;
        builder->ctx().global().jobMgr().waitAll(linkClientId);
        linkInFlight = false;
    }

    ~WorkspaceModuleLink()
    {
        // Defensive drain: an early/error return may drop a link without finalizing it. The job
        // references this object's retained builder, so it must complete before teardown.
        joinLink();
    }
};

namespace
{
    // Foreground completion of a backgrounded module link: drain the link job, interpret its result
    // and report any diagnostics in order, then record the artifact manifest now that the output exists.
    Result finalizeWorkspaceModuleLink(WorkspaceModuleLink& link)
    {
        link.joinLink();

        SWC_RESULT(link.builder->finishDeferredLink());

        if (link.writeManifest && Stats::get().numWarnings.load(std::memory_order_relaxed) == link.warningsBefore)
        {
            collectWorkspaceOutputArtifacts(link.manifest.artifacts, link.outDir);
            SWC_RESULT(writeWorkspaceArtifactManifest(link.builder->ctx(), link.manifest, link.manifestPath));
        }

        return Result::Continue;
    }
}

ExitCode CompilerInstance::runWorkspace()
{
    TaskContext    ctx(*this);
    ScopedTimedLog workspaceStage(ctx, ScopedTimedLog::Stage::Workspace);
    fs::path       workspacePath = cmdLine().workspacePath;
    fs::path       modulesPath   = WorkspaceLayout::workspaceModulesDirectory(workspacePath);
    Utf8           because;

    workspaceBuildLogState_  = {};
    const size_t testsBefore = Stats::get().numTests.load(std::memory_order_relaxed);

    if (FileSystem::resolveExistingFolder(modulesPath, because) != Result::Continue)
    {
        FileSystem::reportPathError(ctx, DiagnosticId::cmd_err_workspace_modules_missing, workspacePath);
        return ExitCode::CompileError;
    }

    std::vector<WorkspaceModuleBuild> modules;
    std::error_code                   ec;
    for (fs::directory_iterator it(modulesPath, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
    {
        if (ec)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_invalid_folder);
            FileSystem::setDiagnosticPathAndBecause(diag, modulesPath, FileSystem::normalizeSystemMessage(ec));
            diag.report(ctx);
            return ExitCode::CompileError;
        }

        const fs::directory_entry& entry = *it;
        if (shouldSkipWorkspaceEntry(entry))
            continue;

        WorkspaceModuleBuild moduleBuild;
        moduleBuild.moduleDir  = FileSystem::normalizePath(entry.path());
        moduleBuild.moduleFile = (moduleBuild.moduleDir / "module.swg").lexically_normal();
        moduleBuild.sourceDir  = (moduleBuild.moduleDir / "src").lexically_normal();
        moduleBuild.name       = moduleBuild.moduleDir.filename().string();

        if (FileSystem::resolveExistingFile(moduleBuild.moduleFile, because) != Result::Continue)
        {
            FileSystem::reportPathError(ctx, DiagnosticId::cmd_err_workspace_module_file_missing, moduleBuild.moduleDir);
            return ExitCode::CompileError;
        }

        if (FileSystem::resolveExistingFolder(moduleBuild.sourceDir, because) != Result::Continue)
        {
            FileSystem::reportPathError(ctx, DiagnosticId::cmd_err_workspace_module_src_missing, moduleBuild.moduleDir);
            return ExitCode::CompileError;
        }

        modules.push_back(std::move(moduleBuild));
    }

    std::ranges::sort(modules, {}, &WorkspaceModuleBuild::name);
    if (modules.empty())
    {
        const Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_no_input);
        diag.report(ctx);
        return ExitCode::CompileError;
    }

    std::set<Utf8> requestedModules = cmdLine().workspaceModuleSelection;
    if (!cmdLine().workspaceModuleFilter.empty())
        requestedModules.insert(cmdLine().workspaceModuleFilter);

    for (const Utf8& requested : requestedModules)
    {
        if (std::ranges::find(modules, requested, &WorkspaceModuleBuild::name) != modules.end())
            continue;

        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_requested_module_missing);
        FileSystem::setDiagnosticPath(diag, workspacePath);
        diag.addArgument(Diagnostic::ARG_SYM, requested);
        diag.report(ctx);
        return ExitCode::CompileError;
    }

    const CommandKind                        command = cmdLine().command;
    const bool                               executableTargetsOnly = requestedModules.empty() && (command == CommandKind::Build || isRunLikeCommand(command));
    std::vector<const WorkspaceModuleBuild*> targets;
    for (WorkspaceModuleBuild& moduleBuild : modules)
    {
        if (!requestedModules.empty() && !requestedModules.contains(moduleBuild.name))
            continue;

        CommandLine setupCmdLine = cmdLine();
        setupCmdLine.rebuild     = cmdLine().rebuild || cmdLine().rebuildModule;
        setupCmdLine.workspacePath.clear();
        setupCmdLine.modulePath     = moduleBuild.moduleDir;
        setupCmdLine.moduleFilePath = moduleBuild.moduleFile;
        setupCmdLine.directories.clear();
        setupCmdLine.files.clear();
        CommandLineParser::refreshBuildCfg(setupCmdLine);

        {
            SWC_SCHED_PHASE(ctx.global().jobMgr(), "workspace module setup");
            if (resolveModuleSetupSnapshot(ctx, setupCmdLine, moduleBuild.moduleFile, moduleBuild.setup) != Result::Continue)
                return ExitCode::CompileError;
        }

        if (moduleBuild.setup.buildCfg.ignoreInWorkspace)
        {
            ++workspaceBuildLogState_.ignoredModules;
            if (requestedModules.empty())
                continue;

            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_requested_module_ignored);
            diag.addArgument(Diagnostic::ARG_SYM, moduleBuild.name);
            diag.report(ctx);
            return ExitCode::CompileError;
        }

        if (executableTargetsOnly && effectiveBackendKind(setupCmdLine, moduleBuild.setup.buildCfg.backendKind) == Runtime::BuildCfgBackendKind::None)
            continue;

        if (prepareSourceDependencies(ctx, moduleBuild.sourceDependencies, moduleBuild.moduleFile, moduleBuild.setup) != Result::Continue)
            return ExitCode::CompileError;
        targets.push_back(&moduleBuild);
    }

    workspaceBuildLogState_.discoveredModules = modules.size();
    workspaceBuildLogState_.activeModules     = targets.size();
    workspaceBuildLogState_.filteredModules   = modules.size() - targets.size() - workspaceBuildLogState_.ignoredModules;
    workspaceStage.setStat(formatWorkspaceStageStat(workspaceBuildLogState_));
    const Logger::ScopedStagesDetailed stagesDetailedScope(global().logger(), targets.size() == 1);

    // A link may overlap the next independent target's front end.
    std::unique_ptr<WorkspaceModuleLink> pendingLink;

    const auto joinPendingLink = [&]() -> Result {
        if (!pendingLink)
            return Result::Continue;
        const std::unique_ptr<WorkspaceModuleLink> link = std::move(pendingLink);
        SWC_SCHED_PHASE(global().jobMgr(), "workspace link wait");
        return finalizeWorkspaceModuleLink(*link);
    };

    const auto buildCount = static_cast<uint32_t>(targets.size());
    for (uint32_t buildIndex = 0; buildIndex < buildCount; ++buildIndex)
    {
        const WorkspaceModuleBuild&          moduleBuild = *targets[buildIndex];
        std::unique_ptr<WorkspaceModuleLink> modulePending;
        bool                                compiled = false;
        const WorkspaceModuleRun moduleRun = {
            .moduleBuild = &moduleBuild,
            .logState    = {.name = moduleBuild.name, .ordinal = buildIndex + 1, .total = buildCount},
        };
        if (runWorkspaceModule(moduleRun, compiled, modulePending) != Result::Continue)
        {
            joinPendingLink();
            return ExitCode::CompileError;
        }

        if (modulePending)
        {
            // Drain the previous in-flight link (it overlapped this module's compilation) before
            // launching this one, keeping the pipeline depth at one.
            if (joinPendingLink() != Result::Continue)
                return ExitCode::CompileError;

            modulePending->launchLink();
            pendingLink = std::move(modulePending);
        }

        workspaceBuildLogState_.builtModules++;
        if (compiled)
            workspaceBuildLogState_.compiledModules++;
        workspaceStage.setStat(formatWorkspaceStageStat(workspaceBuildLogState_));
    }

    if (joinPendingLink() != Result::Continue)
        return ExitCode::CompileError;

    if (cmdLine().command == CommandKind::Test && (!cmdLine().testFileFilter.empty() || !cmdLine().testTagFilter.empty()) && Stats::get().numTests.load(std::memory_order_relaxed) == testsBefore)
    {
        Command::reportTestFilterNoMatch(ctx);
        return ExitCode::CompileError;
    }

    return Stats::getNumErrors() > 0 ? ExitCode::CompileError : ExitCode::Success;
}

Result CompilerInstance::runWorkspaceModule(const WorkspaceModuleRun& moduleRun, bool& outCompiled, std::unique_ptr<WorkspaceModuleLink>& outPending) const
{
    const WorkspaceModuleBuild& moduleBuild = *moduleRun.moduleBuild;
    outPending.reset();
    outCompiled = false;

    CommandLine moduleCmdLine = cmdLine();
    moduleCmdLine.rebuild     = cmdLine().rebuild || cmdLine().rebuildModule;
    moduleCmdLine.modulePath     = moduleBuild.moduleDir;
    moduleCmdLine.moduleFilePath = moduleBuild.moduleFile;
    moduleCmdLine.directories.clear();
    moduleCmdLine.directories.insert(moduleBuild.sourceDir);
    moduleCmdLine.files.clear();
    moduleCmdLine.outDir  = workspaceModuleOutputDirectory(cmdLine().workspacePath, moduleBuild.name, moduleCmdLine, moduleBuild.setup.buildCfg.backendKind, false);
    moduleCmdLine.workDir = workspaceModuleOutputDirectory(cmdLine().workspacePath, moduleBuild.name, moduleCmdLine, moduleBuild.setup.buildCfg.backendKind, true);

    moduleCmdLine.outDirExplicit  = true;
    moduleCmdLine.workDirExplicit = true;
    moduleCmdLine.outDirStorage   = Utf8(moduleCmdLine.outDir);
    moduleCmdLine.workDirStorage  = Utf8(moduleCmdLine.workDir);
    CommandLineParser::refreshBuildCfg(moduleCmdLine);

    const bool            tryReuse = shouldTryReuseWorkspaceArtifacts(moduleCmdLine, moduleBuild.setup.buildCfg.backendKind);
    std::vector<fs::path> currentInputs;
    const auto appendSourceInputs = [&](std::vector<fs::path>& inputs) {
        if (!moduleBuild.sourceDependencies)
            return;
        const auto& sourceInputs = moduleBuild.sourceDependencies->inputs;
        inputs.insert(inputs.end(), sourceInputs.begin(), sourceInputs.end());
        normalizeWorkspacePathsLexically(inputs);
    };
    if (tryReuse)
    {
        collectWorkspaceModuleInputs(currentInputs, moduleCmdLine, moduleBuild.moduleFile, moduleBuild.sourceDir, moduleBuild.setup.loadedFiles, moduleBuild.setup.compilerInputFiles, {});
        appendSourceInputs(currentInputs);
    }

    if (tryReuse)
    {
        CompilerInstance probeCompiler(global(), moduleCmdLine);
        probeCompiler.precomputedModuleSetup_    = &moduleBuild.setup;
        probeCompiler.sourceDependencyPlan_      = moduleBuild.sourceDependencies.get();
        probeCompiler.workspaceModuleLogState_   = moduleRun.logState;

        TaskContext probeCtx(probeCompiler);
        if (probeCompiler.prepareModuleBuildConfig(probeCtx) != Result::Continue)
            return Result::Error;

        std::vector<fs::path> requiredArtifacts;
        fs::path              testArtifactPath;
        fs::path              unexpectedPdbPath;

        const bool needsRequiredArtifact  = moduleCmdLine.command == CommandKind::Build || isRunLikeCommand(moduleCmdLine.command);
        const bool needsTestArtifactProbe = moduleCmdLine.command == CommandKind::Test && probeCompiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable;

        if ((needsRequiredArtifact || needsTestArtifactProbe) &&
            Runtime::backendKindProducesNativeArtifact(probeCompiler.buildCfg().backendKind))
        {
            NativeBackendBuilder        nativeProbeBuilder(probeCompiler, false);
            const NativeArtifactBuilder artifactProbeBuilder(nativeProbeBuilder);
            NativeArtifactPaths         artifactPaths;
            artifactProbeBuilder.queryPaths(artifactPaths);

            if (!probeCompiler.buildCfg().backend.debugInfo &&
                probeCompiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable)
                unexpectedPdbPath = artifactPaths.pdbPath;

            if (needsRequiredArtifact)
            {
                requiredArtifacts.push_back(artifactPaths.artifactPath);

                if (probeCompiler.buildCfg().backend.debugInfo && !artifactPaths.pdbPath.empty())
                    requiredArtifacts.push_back(artifactPaths.pdbPath);

                probeCompiler.setLastArtifactLabel(artifactPaths.artifactLabel());
            }
            else
            {
                testArtifactPath = artifactPaths.artifactPath;
            }
        }

        WorkspaceArtifactManifest manifest;
        const fs::path            manifestPath = workspaceArtifactManifestPath(moduleCmdLine.outDir, moduleCmdLine);
        std::error_code           unexpectedPdbError;
        const bool                hasUnexpectedPdb = !unexpectedPdbPath.empty() && fs::exists(unexpectedPdbPath, unexpectedPdbError);
        WorkspaceArtifactState    artifactState    = WorkspaceArtifactState::Stale;
        if (!hasUnexpectedPdb && !unexpectedPdbError && readWorkspaceArtifactManifest(manifest, manifestPath))
            artifactState = workspaceArtifactState(manifest, moduleCmdLine.outDir, manifestPath, exeFullName_, currentInputs, requiredArtifacts, workspaceArtifactConfiguration(probeCompiler), moduleCmdLine.tags);

        if (artifactState == WorkspaceArtifactState::UpToDate)
        {
            const bool     runReusedTestArtifact = !testArtifactPath.empty() && workspaceManifestContainsArtifact(manifest, moduleCmdLine.outDir, testArtifactPath);
            ScopedTimedLog moduleStage(probeCtx, ScopedTimedLog::Stage::Module);
            if (isRunLikeCommand(moduleCmdLine.command))
            {
                NativeBackendBuilder runBuilder(probeCompiler, true);
                SWC_RESULT(runBuilder.runExistingArtifact());
            }

            if (runReusedTestArtifact)
            {
                NativeBackendBuilder testBuilder(probeCompiler, true);
                const Result         testResult = testBuilder.runExistingArtifact();

                // The successful compile that wrote the manifest already checked the static
                // test count. The reused artifact's fresh tally proves that it ran again.
                Stats::get().numTests.fetch_add(testBuilder.nativeTestsExecuted, std::memory_order_relaxed);
                Stats::get().numTestsFailed.fetch_add(testBuilder.nativeTestsFailed, std::memory_order_relaxed);
                if (testResult != Result::Continue)
                    return Result::Error;
            }

            moduleStage.markUpToDate();
            moduleStage.setStat(formatWorkspaceArtifactStat(probeCompiler));
            return Result::Continue;
        }

    }

    const uint64_t errorsBefore   = Stats::getNumErrors();
    const size_t   warningsBefore = Stats::get().numWarnings.load(std::memory_order_relaxed);

    // The compiler outlives this call when its link is deferred (the builder holds a pointer to it,
    // and the compiler holds a pointer to the CommandLine), so both are heap-owned and handed to the
    // caller in the pending link. Native-artifact builds run only the build half here and leave a
    // prepared link to be executed off the main thread.
    auto moduleCmdLineOwned                    = std::make_unique<CommandLine>(moduleCmdLine);
    auto moduleCompiler                        = std::make_unique<CompilerInstance>(global(), *moduleCmdLineOwned);
    moduleCompiler->precomputedModuleSetup_    = &moduleBuild.setup;
    moduleCompiler->sourceDependencyPlan_      = moduleBuild.sourceDependencies.get();
    moduleCompiler->workspaceModuleLogState_   = moduleRun.logState;
    moduleCompiler->setDeferNativeLink(true);
    outCompiled = true;

    std::unique_ptr<NativeBackendBuilder> deferredBuilder;
    {
        TaskContext    moduleCtx(*moduleCompiler);
        ScopedTimedLog moduleStage(moduleCtx, ScopedTimedLog::Stage::Module);
        {
            SWC_SCHED_PHASE(global().jobMgr(), "module command");
            moduleCompiler->processCommand();
        }
        if (moduleCompiler->flushGeneratedSourceDumps(moduleCtx) != Result::Continue)
            return Result::Error;
        moduleStage.setStat(formatWorkspaceModuleStageStat(moduleCtx, *moduleCompiler, moduleStage.delta()));
        const bool commandFailed = Stats::getNumErrors() != errorsBefore;
        // An artifact hit skips semantic analysis, so a build that reported warnings
        // needs to run that phase again on the next invocation.
        const bool canWriteManifest = Stats::get().numWarnings.load(std::memory_order_relaxed) == warningsBefore &&
                                      shouldWriteWorkspaceArtifactManifest(*moduleCompiler);

        deferredBuilder = moduleCompiler->takeDeferredBuilder();
        if (!deferredBuilder)
        {
            // No deferred link to finalize (non-native backend, or a test run): finalize synchronously,
            // exactly as before. The artifacts, if any, were already produced by processCommand.
            // A test executable is a successful build even when running it reports a failing
            // test. Persist that build manifest so the next test run reuses and re-executes the
            // same artifact, exactly as `run` reuses an executable whose program returned nonzero.
            if (canWriteManifest && (!commandFailed || moduleCompiler->nativeArtifactBuilt()))
            {
                WorkspaceArtifactManifest manifest;
                manifest.inputsReadTime       = moduleBuild.setup.inputsReadTime;
                manifest.configuration   = workspaceArtifactConfiguration(*moduleCompiler);
                manifest.tagsFingerprint = workspaceTagsFingerprint(moduleCmdLine.tags);
                collectWorkspaceModuleInputs(manifest.inputs, moduleCmdLine, moduleBuild.moduleFile, moduleBuild.sourceDir, moduleBuild.setup.loadedFiles, moduleBuild.setup.compilerInputFiles, moduleCompiler->compilerInputFiles());
                appendSourceInputs(manifest.inputs);
                collectWorkspaceOutputArtifacts(manifest.artifacts, moduleCmdLine.outDir);
                if (writeWorkspaceArtifactManifest(moduleCtx, manifest, workspaceArtifactManifestPath(moduleCmdLine.outDir, moduleCmdLine)) != Result::Continue)
                    return Result::Error;
            }

            return commandFailed ? Result::Error : Result::Continue;
        }

        if (commandFailed)
            return Result::Error;

        // Capture the manifest inputs now, while the compiler state is fully available; the artifact
        // list and the manifest write happen once the background link finishes (finalizeWorkspaceModuleLink).
        auto link            = std::make_unique<WorkspaceModuleLink>();
        link->moduleName     = moduleBuild.name;
        link->outDir         = moduleCmdLine.outDir;
        link->manifestPath   = workspaceArtifactManifestPath(moduleCmdLine.outDir, moduleCmdLine);
        link->writeManifest  = canWriteManifest;
        link->warningsBefore = warningsBefore;
        if (link->writeManifest)
        {
            link->manifest.inputsReadTime       = moduleBuild.setup.inputsReadTime;
            link->manifest.configuration   = workspaceArtifactConfiguration(*moduleCompiler);
            link->manifest.tagsFingerprint = workspaceTagsFingerprint(moduleCmdLine.tags);
            collectWorkspaceModuleInputs(link->manifest.inputs, moduleCmdLine, moduleBuild.moduleFile, moduleBuild.sourceDir, moduleBuild.setup.loadedFiles, moduleBuild.setup.compilerInputFiles, moduleCompiler->compilerInputFiles());
            appendSourceInputs(link->manifest.inputs);
        }

        link->builder  = std::move(deferredBuilder);
        link->compiler = std::move(moduleCompiler);
        link->cmdLine  = std::move(moduleCmdLineOwned);
        outPending     = std::move(link);
    }

    return Result::Continue;
}

Result CompilerInstance::registerModuleSetupImport(const std::string_view moduleName, const std::string_view location)
{
    if (moduleName.empty())
        return Result::Continue;

    fs::path baseDir;
    if (!modulePathFile_.empty())
        baseDir = modulePathFile_.parent_path();
    else if (!cmdLine().moduleFilePath.empty())
        baseDir = cmdLine().moduleFilePath.parent_path();
    else
        baseDir = FileSystem::currentPathNoThrow();

    if (!baseDir.empty())
        baseDir = FileSystem::normalizePath(baseDir);

    const std::scoped_lock lock(moduleInputsMutex_);
    for (const ModuleSetupImport& existingImport : moduleSetupImports_)
    {
        if (existingImport.moduleName == moduleName &&
            existingImport.location == location &&
            FileSystem::pathEquals(existingImport.baseDir, baseDir))
            return Result::Continue;
    }

    ModuleSetupImport importRequest;
    importRequest.moduleName      = moduleName;
    importRequest.location        = location;
    importRequest.baseDir         = std::move(baseDir);
    moduleSetupImports_.push_back(std::move(importRequest));
    return Result::Continue;
}

Result CompilerInstance::registerModuleSetupLoad(const fs::path& filePath)
{
    if (filePath.empty())
        return Result::Continue;

    const fs::path         normalizedPath = FileSystem::normalizePath(filePath);
    const std::scoped_lock lock(moduleInputsMutex_);
    moduleSetupLoadedFiles_.insert(normalizedPath);
    return Result::Continue;
}

std::vector<CompilerInstance::ModuleSetupImport> CompilerInstance::moduleSetupImports() const
{
    const std::scoped_lock lock(moduleInputsMutex_);
    return moduleSetupImports_;
}

std::set<fs::path> CompilerInstance::moduleSetupLoadedFiles() const
{
    const std::scoped_lock lock(moduleInputsMutex_);
    return moduleSetupLoadedFiles_;
}

void CompilerInstance::appendBuildConfigCacheIdentity(ByteArray& out) const
{
    const auto& cfg = buildCfg();
    out.appendLe32(cfg.moduleVersion);
    out.appendLe32(cfg.moduleRevision);
    out.appendLe32(cfg.moduleBuildNum);
    out.appendLe32(cfg.ignoreInWorkspace);
    out.appendLe32(cfg.tempAllocatorCapacity);
    out.appendLe32(cfg.errorAllocatorCapacity);
    out.appendLe32(static_cast<uint32_t>(cfg.safetyGuards));
    out.appendLe32(static_cast<uint32_t>(cfg.sanityGuards));
    out.appendLe32(cfg.allocatorCaptureStack);
    out.appendLe32(cfg.allocatorLeaks);
    out.appendLe32(cfg.allocatorTrackAllocations);
    out.appendLe32(cfg.allocatorElectricMode);
    out.appendLe32(cfg.allocatorFillMemory);
    out.appendLe32(cfg.errorStackTrace);
    out.appendLe32(static_cast<uint32_t>(cfg.backendKind));
    out.appendLe32(static_cast<uint32_t>(cfg.backendSubKind));
    cfg.backend.appendCacheIdentity(out);

    const auto& doc = cfg.genDoc;
    out.appendLe32(static_cast<uint32_t>(doc.kind));
    out.appendLe32(doc.syntaxDefaultColor);
    out.appendLe32(std::bit_cast<uint32_t>(doc.syntaxColorLum));
    out.appendLe32(doc.accentColor);
    out.appendLe32(static_cast<uint32_t>(doc.theme));
    out.appendLe32(doc.hasSwagWatermark);
    out.appendLe32(doc.hasSymbolIndex);
    out.appendLe32(doc.hasSearch);

    visitBuildCfgStrings(cfg, [&out](const Runtime::String& value) {
        out.appendLe32(value.ptr != nullptr);
        out.appendLe64(value.length);
        if (value.ptr && value.length)
            out.append(std::string_view(value.ptr, value.length));
    });
}

void CompilerInstance::registerCompilerInputFile(const fs::path& filePath, std::optional<std::span<const std::byte>> contents)
{
    if (filePath.empty())
        return;
    if (semaBodyCache_)
        semaBodyCache_->recordInput();

    const fs::path normalizedPath = FileSystem::normalizePath(filePath);
    const auto     checksum       = moduleSetupMode_ && contents ? std::optional{sha256(*contents)} : std::nullopt;

    const std::scoped_lock lock(moduleInputsMutex_);
    compilerInputFiles_.insert(normalizedPath);
    if (checksum)
    {
        const auto [entry, inserted] = moduleSetupInputChecksums_.try_emplace(normalizedPath, *checksum);
        if (!inserted && entry->second != *checksum)
            moduleSetupInputsConsistent_ = false;
    }
    else if (moduleSetupMode_)
    {
        moduleSetupInputsConsistent_ = false;
    }
}

std::set<fs::path> CompilerInstance::compilerInputFiles() const
{
    const std::scoped_lock lock(moduleInputsMutex_);
    return compilerInputFiles_;
}

Result CompilerInstance::validateAllocatorConfig(TaskContext& ctx) const
{
    if (findCompilerTag("Swag.AllocatorDiagnostics"))
        return Result::Continue;
    if (!buildCfg_.allocatorCaptureStack && !buildCfg_.allocatorLeaks && !buildCfg_.allocatorTrackAllocations &&
        !buildCfg_.allocatorElectricMode && !buildCfg_.allocatorFillMemory)
        return Result::Continue;

    Diagnostic::get(DiagnosticId::cmd_err_allocator_diagnostics_tag).report(ctx);
    return Result::Error;
}

void CompilerInstance::adoptBuildCfg(const Runtime::BuildCfg& buildCfg)
{
    buildCfg_ = buildCfg;
    ownBuildCfgStrings(buildCfg_, ownedBuildCfgStrings_);
}

Result CompilerInstance::adoptModuleBuildCfg(TaskContext& ctx, const Runtime::BuildCfg& buildCfg)
{
    adoptBuildCfg(buildCfg);
    reapplyExplicitBuildCfgOverrides(buildCfg_, cmdLine());
    ownBuildCfgStrings(buildCfg_, ownedBuildCfgStrings_);

    struct WarningField
    {
        const Runtime::String* value;
        WarningLevel           level;
        std::string_view       name;
    };

    // Read in this order, so the last field that names a warning decides it.
    const WarningField fields[] = {
        {&buildCfg_.warnings.asErrors, WarningLevel::Error, "asErrors"},
        {&buildCfg_.warnings.asWarnings, WarningLevel::Warning, "asWarnings"},
        {&buildCfg_.warnings.disabled, WarningLevel::Disable, "disabled"},
    };

    warningPolicy_.reset();

    for (const WarningField& field : fields)
    {
        if (!field.value->ptr || !field.value->length)
            continue;

        const std::string_view    names   = {field.value->ptr, field.value->length};
        const std::optional<Utf8> unknown = warningPolicy_.addList(names, field.level);
        if (!unknown.has_value())
            continue;

        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_build_cfg_unknown_warning);
        diag.addArgument(Diagnostic::ARG_ARG, field.name);
        diag.addArgument(Diagnostic::ARG_VALUE, unknown.value());
        diag.addDidYouMeanNote(Utf8Helper::bestMatch(unknown.value(), WarningPolicy::allIdNames()));
        diag.report(ctx);
        return Result::Error;
    }

    return Result::Continue;
}

// Adds the files a setup '#load' named and that have not been read yet, parses them, and returns
// them ready for semantic analysis.
//
// They are flagged like the setup file itself, so their own '#import' and '#load' are directives
// the setup pass acts on rather than statements it refuses.
Result CompilerInstance::collectModuleSetupLoadedFiles(TaskContext& ctx, const std::set<fs::path>& alreadyRead, std::vector<SourceFile*>& outFiles)
{
    std::vector<SourceFile*> added;
    for (const fs::path& filePath : moduleSetupLoadedFiles())
    {
        const fs::path normalizedPath = FileSystem::normalizePath(filePath);
        if (alreadyRead.contains(normalizedPath) || hasResolvedFilePath(normalizedPath))
            continue;

        SourceFile& file = addResolvedFile(normalizedPath, FileFlagsE::Module | FileFlagsE::SetupLoaded);
        added.push_back(&file);
    }

    if (added.empty())
        return Result::Continue;

    const uint64_t errorsBefore = Stats::getNumErrors();
    parseSourceFiles(ctx, added);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    for (SourceFile* file : added)
    {
        const SourceView& srcView = file->ast().srcView();
        if (srcView.mustSkip() || !srcView.runsSema() || file->hasError())
            continue;
        outFiles.push_back(file);
    }

    return Result::Continue;
}

Result CompilerInstance::captureModuleSetupSnapshot(const TaskContext& ctx, const CommandLine& setupCmdLine, ModuleSetupSnapshot& outSnapshot) const
{
    SWC_UNUSED(ctx);
    outSnapshot                = {};
    outSnapshot.inputsReadTime = std::chrono::floor<Os::FileChangeTime::duration>(std::chrono::system_clock::now());
    CompilerInstance setupCompiler(global(), setupCmdLine);
    setupCompiler.moduleSetupMode_ = true;
    struct ConstCallCacheResetGuard
    {
        ~ConstCallCacheResetGuard()
        {
            SemaJIT::clearConstCallCache();
        }
    } constCallCacheResetGuard;

    TaskContext setupCtx(setupCompiler);
    SWC_RESULT(setupCompiler.collectFiles(setupCtx));

    const Global&     global       = setupCtx.global();
    JobManager&       jobMgr       = global.jobMgr();
    const JobClientId clientId     = setupCompiler.jobClientId();
    const uint64_t    errorsBefore = Stats::getNumErrors();

    parseSourceFiles(setupCtx, setupCompiler.files());
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    std::vector<SourceFile*> files;
    files.reserve(setupCompiler.files().size());
    for (SourceFile* file : setupCompiler.files())
    {
        const SourceView& srcView = file->ast().srcView();
        if (srcView.mustSkip())
            continue;
        if (!srcView.runsSema())
            continue;
        if (file->hasError())
            continue;
        files.push_back(file);
    }

    // What the setup leaves behind: the build configuration, owning its strings, and what it imported and read.
    const auto captureSnapshot = [&] {
        outSnapshot.buildCfg           = setupCompiler.buildCfg();
        outSnapshot.imports            = setupCompiler.moduleSetupImports();
        outSnapshot.loadedFiles        = setupCompiler.moduleSetupLoadedFiles();
        outSnapshot.compilerInputFiles = setupCompiler.compilerInputFiles();
        ownBuildCfgStrings(outSnapshot.buildCfg, outSnapshot.ownedStrings);

        // A setup that emits diagnostics or writes through the JIT must run again
        // so its externally visible effects occur on every invocation.
        if (!setupCompiler.moduleSetupInputsConsistent_ || setupCompiler.jitHasUntrackedEffects() || !setupCompiler.reportedDiagnostics_.empty())
            return;

        auto& checksums = outSnapshot.inputChecksums;
        checksums       = std::move(setupCompiler.moduleSetupInputChecksums_);
        for (const SourceFile* file : setupCompiler.files())
        {
            if (!file->hasFlag(FileFlagsE::Module) || file->hasFlag(FileFlagsE::CustomSrc) || !file->ast().hasSourceView())
                continue;

            const fs::path path = FileSystem::normalizePath(file->path());
            const auto checksum = setupCompiler.sourceFileChecksum(*file);
            const auto [entry, inserted] = checksums.try_emplace(path, checksum);
            if (!inserted && entry->second != checksum)
            {
                checksums.clear();
                return;
            }
        }
    };

    if (files.empty())
    {
        captureSnapshot();
        return Result::Continue;
    }

    SWC_RESULT(setupCompiler.setupSema(setupCtx));

    auto*      symModule           = Symbol::make<SymbolModule>(setupCtx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    const Utf8 moduleNamespaceName = setupCompiler.moduleNamespaceName();

    constexpr SymbolFlags namespaceFlags  = SymbolFlagsE::Declared | SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted;
    const IdentifierRef   idRef           = setupCtx.idMgr().addIdentifierOwned(moduleNamespaceName, Math::hash(moduleNamespaceName));
    auto*                 moduleNamespace = Symbol::make<SymbolNamespace>(setupCtx, nullptr, TokenRef::invalid(), idRef, namespaceFlags);
    symModule->addSingleSymbol(setupCtx, moduleNamespace);
    setupCompiler.setSymModule(symModule);

    // Empty-named root namespace hosting symbols imported from other modules (see importRootNamespace).
    // Owned by the module symbol (like the module namespace) so it is treated as a module-root when
    // collecting namespace paths (collectSymbolMapNamespacePath) and contributes no name prefix.
    auto* importRootNamespace = Symbol::make<SymbolNamespace>(setupCtx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), namespaceFlags);
    importRootNamespace->setOwnerSymMap(symModule);
    setupCompiler.setImportRootNamespace(importRootNamespace);

    // '#load' nests: a loaded file states its own imports and loads, and they are only known once
    // that file has been read. So each round sema's what is known and then looks at what it
    // discovered; a round that discovers nothing new ends the walk. A file is added once, which is
    // what makes a cycle between two files that load each other terminate rather than spin.
    std::set<fs::path> semaDone;
    while (!files.empty())
    {
        for (SourceFile* file : files)
        {
            semaDone.insert(FileSystem::normalizePath(file->path()));
            file->setModuleNamespace(*moduleNamespace);
            auto* job = setupCompiler.makeJob<SemaJob>(setupCtx, file->nodePayloadContext(), true);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);
        if (Stats::getNumErrors() != errorsBefore)
            return Result::Error;

        for (SourceFile* file : files)
        {
            auto* job = setupCompiler.makeJob<SemaJob>(setupCtx, file->nodePayloadContext(), false);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        Sema::waitDone(setupCtx, clientId);
        if (Stats::getNumErrors() != errorsBefore)
            return Result::Error;

        files.clear();
        SWC_RESULT(setupCompiler.collectModuleSetupLoadedFiles(setupCtx, semaDone, files));
    }

    SWC_RESULT(setupCompiler.validateAllocatorConfig(setupCtx));
    captureSnapshot();
    return Result::Continue;
}

// Answers a module's setup from the cache when its inputs, the command line and the compiler
// are the ones that produced it, and runs the setup otherwise. A '--rebuild' never reads the
// cache, so the one command that promises to redo everything redoes this too; it still writes
// it, since the next command is not a rebuild.
Result CompilerInstance::resolveModuleSetupSnapshot(const TaskContext& ctx, const CommandLine& setupCmdLine, const fs::path& moduleFile, ModuleSetupSnapshot& outSnapshot) const
{
    ModuleSetupSnapshot literalImports;
    literalImports.inputsReadTime = std::chrono::floor<Os::FileChangeTime::duration>(std::chrono::system_clock::now());
    if (tryCaptureLiteralModuleImports(moduleFile, literalImports.imports))
    {
        literalImports.buildCfg = setupCmdLine.defaultBuildCfg;
        ownBuildCfgStrings(literalImports.buildCfg, literalImports.ownedStrings);
        outSnapshot = std::move(literalImports);
        return Result::Continue;
    }

    const Utf8 key = moduleSetupCacheKey(setupCmdLine, moduleFile, exeFullName_);
    if (key.empty())
        return captureModuleSetupSnapshot(ctx, setupCmdLine, outSnapshot);

    if (!setupCmdLine.rebuild)
    {
        ModuleSetupSnapshot cached;
        cached.inputsReadTime = literalImports.inputsReadTime;
        if (readModuleSetupCache(cached, key, moduleFile))
        {
            outSnapshot = std::move(cached);
            return Result::Continue;
        }
    }

    SWC_RESULT(captureModuleSetupSnapshot(ctx, setupCmdLine, outSnapshot));
    writeModuleSetupCache(key, moduleFile, outSnapshot);
    return Result::Continue;
}

Result CompilerInstance::resolveModuleInputPaths(TaskContext& ctx)
{
    const CommandLine& cmdLine = ctx.cmdLine();
    if (!cmdLine.moduleFilePath.empty())
    {
        if (modulePathFile_.empty())
        {
            modulePathFile_ = cmdLine.moduleFilePath;
            SWC_RESULT(FileSystem::resolveFile(ctx, modulePathFile_));
        }

        return Result::Continue;
    }

    if (cmdLine.modulePath.empty())
        return Result::Continue;

    if (modulePathFile_.empty())
    {
        modulePathFile_ = cmdLine.modulePath / "module.swg";
        SWC_RESULT(FileSystem::resolveFile(ctx, modulePathFile_));
    }

    if (modulePathSrc_.empty())
    {
        modulePathSrc_ = cmdLine.modulePath / "src";
        Utf8 because;
        if (FileSystem::resolveExistingFolder(modulePathSrc_, because) != Result::Continue)
            modulePathSrc_.clear();
    }

    return Result::Continue;
}

Result CompilerInstance::runModuleSetup(TaskContext& ctx)
{
    SWC_RESULT(resolveModuleInputPaths(ctx));
    if (modulePathFile_.empty())
        return Result::Continue;

    if (precomputedModuleSetup_)
    {
        SWC_RESULT(adoptModuleBuildCfg(ctx, precomputedModuleSetup_->buildCfg));
        applySourceDependencies(*precomputedModuleSetup_);
        return Result::Continue;
    }

    CommandLine setupCmdLine = cmdLine();
    setupCmdLine.directories.clear();
    setupCmdLine.files.clear();
    setupCmdLine.moduleFilePath = modulePathFile_;
    setupCmdLine.modulePath     = modulePathFile_.parent_path();
    CommandLineParser::refreshBuildCfg(setupCmdLine);

    ModuleSetupSnapshot setupSnapshot;
    SWC_RESULT(resolveModuleSetupSnapshot(ctx, setupCmdLine, modulePathFile_, setupSnapshot));
    SWC_RESULT(adoptModuleBuildCfg(ctx, setupSnapshot.buildCfg));
    SWC_RESULT(prepareSourceDependencies(ctx, ownedSourceDependencyPlan_, modulePathFile_, setupSnapshot));
    sourceDependencyPlan_ = ownedSourceDependencyPlan_.get();
    applySourceDependencies(setupSnapshot);
    return Result::Continue;
}

// Adopts the module build configuration without applying its input set. This is the cheap
// half of runModuleSetup: it makes buildCfg() (backend kind, debug info, artifact naming)
// available so the workspace up-to-date probe can compute artifact paths before loading sources.
Result CompilerInstance::prepareModuleBuildConfig(TaskContext& ctx)
{
    SWC_RESULT(resolveModuleInputPaths(ctx));
    if (modulePathFile_.empty() || cmdLine().moduleFilePath.empty())
        return Result::Continue;

    SWC_ASSERT(precomputedModuleSetup_ != nullptr);
    return adoptModuleBuildCfg(ctx, precomputedModuleSetup_->buildCfg);
}

void CompilerInstance::appendResolvedFiles(std::vector<fs::path>& paths, FileFlags flags)
{
    if (paths.empty())
        return;

    files_.reserve(files_.size() + paths.size());
    for (fs::path& path : paths)
    {
        if (hasResolvedFilePath(path))
            continue;
        addResolvedFile(std::move(path), flags);
    }
}

void CompilerInstance::collectFolderFiles(const fs::path& folder, FileFlags flags, const bool canFilter)
{
    std::vector<fs::path> paths;
    collectSwagFilesRec(cmdLine(), folder, paths, canFilter);
    std::ranges::sort(paths);
    appendResolvedFiles(paths, flags);
}

Result CompilerInstance::collectFiles(TaskContext& ctx)
{
    const CommandLine& cmdLine        = ctx.cmdLine();
    const FileFlags    directSrcFlags = cmdLine.moduleFilePath.empty() ? FileFlagsE::CustomSrc : FileFlagsE::ModuleSrc;

    // Collect direct folders from the command line
    for (const fs::path& folder : cmdLine.directories)
        collectFolderFiles(folder, directSrcFlags, true);

    // Collect direct files from the command line
    if (!cmdLine.files.empty())
    {
        files_.reserve(files_.size() + cmdLine.files.size());
        for (const fs::path& file : cmdLine.files)
        {
            if (hasResolvedFilePath(file))
                continue;
            addResolvedFile(file, directSrcFlags);
        }
    }

    // Collect files for the module
    SWC_RESULT(resolveModuleInputPaths(ctx));
    if (!modulePathFile_.empty())
    {
        if (!hasResolvedFilePath(modulePathFile_))
            addResolvedFile(modulePathFile_, FileFlagsE::Module);
    }
    if (!cmdLine.modulePath.empty())
    {
        if (!modulePathSrc_.empty())
            collectFolderFiles(modulePathSrc_, FileFlagsE::ModuleSrc, true);
    }

    // Collect runtime files. The runtime bootstrap (which declares compiler intrinsics such
    // as `Swag.compiler()`) must always be part of the input set, including the module-setup pass
    // that runs module-setup directives and `#run` blocks, so those blocks can reach it too.
    {
        fs::path runtimePath = FileSystem::compilerResourceRoot(exeFullName_) / "runtime";
        SWC_RESULT(FileSystem::resolveFolder(ctx, runtimePath));
        collectFolderFiles(runtimePath, FileFlagsE::Runtime, false);
    }

    srcViews_.reserve(files_.size());

    if (files_.empty())
    {
        const Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_no_input);
        diag.report(ctx);
        return Result::Error;
    }

    return Result::Continue;
}

Result CompilerInstance::collectDocumentation(TaskContext& ctx)
{
    const Result result = ModuleApi::collectPublicEntries(ctx, ctx.compiler().prepareModuleApiPublicEntries());

    // Documentation uses the reachable-node indexes only during collection.
    for (SourceFile* file : ctx.compiler().files())
    {
        if (file)
            file->ast().releaseReachableNodeIndex();
    }

    return result;
}

SWC_END_NAMESPACE();
