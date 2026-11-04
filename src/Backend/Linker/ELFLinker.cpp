#include "pch.h"
#include "Backend/Linker/ELFLinker.h"
#include "Backend/Linker/ELFObjectWriter.h"
#include "Backend/Linker/ELFSymbolTable.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeElfFunctionCache.h"
#include "Backend/Native/NativeNames.h"
#include "Backend/RuntimeName.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerCache.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Support/Math/Sha256.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void takeObjects(std::vector<LinkArchiveMember>& members, NativeBackendBuilder& builder)
    {
        members.reserve(builder.objectDescriptions.size());
        for (NativeObjDescription& object : builder.objectDescriptions)
            members.push_back({.name = Utf8(object.objPath.filename()), .bytes = std::move(object.objBytes)});
    }

    void collectLibraries(std::set<Utf8>& libraries, const TaskContext& ctx, const MachineCode& code)
    {
        for (const MicroRelocation& relocation : code.codeRelocations)
        {
            if (relocation.kind != MicroRelocation::Kind::ForeignFunctionAddress || !relocation.targetSymbol)
                continue;
            const auto* function = relocation.targetSymbol->safeCast<SymbolFunction>();
            if (!function)
                continue;
            Utf8 name(function->foreignLinkModuleName());
            if (name.empty())
                name = Utf8(ctx.compiler().runtimeImportLinkName(function->resolveForeignModuleName(ctx).view()));
            if (!name.empty())
                libraries.insert(std::move(name));
        }
    }

    fs::path resolveDependencyLibrary(const fs::path& name, const std::vector<fs::path>& directories)
    {
        // Swag publishes module.a/module.so, without GNU's optional lib prefix.
        // Keep the selected dependency directory authoritative, including test and
        // renamed artifacts, before falling back to the system linker's search.
        for (const fs::path& directory : directories)
        {
            for (const std::string_view extension : {"", ".so", ".a"})
            {
                const fs::path candidate = directory / (name.string() + std::string(extension));
                std::error_code error;
                if (fs::is_regular_file(candidate, error))
                    return fs::absolute(candidate);
            }
        }
        return {};
    }

    constexpr uint64_t K_RELINK_MAGIC       = 0x314b4e4c45435753; // SWCELNK1
    constexpr size_t   K_RELINK_HEADER_SIZE = 40;

    bool buildRelinkCache(ByteArray& bytes, const std::vector<LinkArchiveMember>& objects)
    {
        const Utf8& identity = compilerCacheIdentity();
        if (identity.empty() || identity.size() > UINT32_MAX || objects.empty() || objects.size() > UINT32_MAX)
            return false;
        bytes.appendLe64(K_RELINK_MAGIC);
        bytes.resize(K_RELINK_HEADER_SIZE);
        bytes.appendLe32(static_cast<uint32_t>(identity.size()));
        bytes.append(identity.view());
        bytes.appendLe32(static_cast<uint32_t>(objects.size()));
        for (const LinkArchiveMember& object : objects)
        {
            bytes.appendLe64(object.bytes.size());
            bytes.append(object.bytes.span());
        }
        const auto checksum = sha256(bytes.span().subspan(K_RELINK_HEADER_SIZE));
        std::memcpy(bytes.data() + 8, checksum.data(), checksum.size());
        return true;
    }

    bool readRelinkCache(std::vector<LinkArchiveMember>& outObjects, const ByteArray& bytes)
    {
        if (!bytes.containsRange(0, K_RELINK_HEADER_SIZE + 4) || bytes.readLe64(0) != K_RELINK_MAGIC)
            return false;
        const auto checksum = sha256(bytes.span().subspan(K_RELINK_HEADER_SIZE));
        if (std::memcmp(bytes.data() + 8, checksum.data(), checksum.size()) != 0)
            return false;
        const Utf8&    identity     = compilerCacheIdentity();
        const uint32_t identitySize = bytes.readLe32(K_RELINK_HEADER_SIZE);
        size_t         cursor       = K_RELINK_HEADER_SIZE + 4;
        if (identity.empty() || identitySize != identity.size() || !bytes.containsRange(cursor, identitySize) || std::memcmp(bytes.data() + cursor, identity.data(), identitySize) != 0)
            return false;
        cursor += identitySize;
        if (!bytes.containsRange(cursor, 4))
            return false;
        const uint32_t count = bytes.readLe32(cursor);
        cursor += 4;
        if (!count || count > (bytes.size() - cursor) / 72)
            return false;
        std::vector<LinkArchiveMember> objects;
        objects.reserve(count);
        for (uint32_t index = 0; index < count; ++index)
        {
            if (!bytes.containsRange(cursor, 8))
                return false;
            const uint64_t size = bytes.readLe64(cursor);
            cursor += 8;
            if (size < 64 || !bytes.containsRange(cursor, size) || bytes.readLe32(cursor) != 0x464c457f ||
                bytes[cursor + 4] != std::byte{2} || bytes[cursor + 5] != std::byte{1} || bytes.readLe16(cursor + 16) != 1 || bytes.readLe16(cursor + 18) != 62)
                return false;
            LinkArchiveMember object;
            object.name = std::format("relinked_{:06}.o", index);
            object.bytes.append(bytes.span().subspan(cursor, size));
            objects.push_back(std::move(object));
            cursor += size;
        }
        if (cursor != bytes.size())
            return false;
        outObjects = std::move(objects);
        return true;
    }

    void appendLibraryArguments(LinkJob& job, const CompilerInstance& compiler, const std::set<Utf8>& libraries)
    {
        std::set<fs::path> archives;
        for (const fs::path& directory : compiler.importedDependencyLinkDirs())
        {
            job.elfLinkArguments.emplace_back("-L" + Utf8(fs::absolute(directory)));
            // -L does not resolve DT_NEEDED entries of imported shared libraries. Keep this
            // search path link-only so deployed artifacts retain their $ORIGIN runpath.
            job.elfLinkArguments.emplace_back("-Xlinker");
            job.elfLinkArguments.emplace_back("-rpath-link");
            job.elfLinkArguments.emplace_back("-Xlinker");
            job.elfLinkArguments.emplace_back(Utf8(fs::absolute(directory)));
            std::error_code error;
            for (fs::directory_iterator it(directory, fs::directory_options::skip_permission_denied, error), end; it != end && !error; it.increment(error))
            {
                if (it->is_regular_file(error) && it->path().extension() == ".a")
                    archives.insert(fs::absolute(it->path()));
            }
        }
        job.elfLinkArguments.emplace_back("-Wl,--start-group");
        for (const fs::path& archive : archives)
            job.elfLinkArguments.emplace_back(archive);
        for (const Utf8& library : libraries)
        {
            const fs::path name(library.c_str());
            if (name.has_parent_path())
                job.elfLinkArguments.emplace_back(fs::absolute(name));
            else
            {
                const fs::path dependency = resolveDependencyLibrary(name, compiler.importedDependencyLinkDirs());
                if (!dependency.empty())
                {
                    if (!archives.contains(dependency))
                        job.elfLinkArguments.emplace_back(dependency);
                }
                else if (name.has_extension())
                    job.elfLinkArguments.emplace_back("-l:" + library);
                else
                    job.elfLinkArguments.emplace_back("-l" + library);
            }
        }
        job.elfLinkArguments.emplace_back("-Wl,--end-group");
    }

    bool writeBytes(LinkJob& job, const fs::path& path, const ByteArray& bytes)
    {
        FileSystem::IoErrorInfo error;
        if (FileSystem::writeBinaryFile(path, bytes.data(), bytes.size(), error) == Result::Continue)
            return true;
        job.error = Diagnostic::get(DiagnosticId::cmd_err_link_artifact_write_failed);
        job.error.addArgument(Diagnostic::ARG_PATH, Utf8(path));
        job.error.addArgument(Diagnostic::ARG_BECAUSE, FileSystem::describeIoFailure(error));
        return false;
    }

    bool linkError(LinkJob& job, std::string_view reason)
    {
        job.error = Diagnostic::get(DiagnosticId::cmd_err_link_external_failed);
        job.error.addArgument(Diagnostic::ARG_PATH, Utf8(job.outputPath));
        job.error.addArgument(Diagnostic::ARG_BECAUSE, Utf8(reason));
        return false;
    }

    bool runTool(LinkJob& job, std::string_view tool, const std::vector<Utf8>& arguments, const fs::path& directory)
    {
        // GNU response files keep argument count independent of the process argv limit.
        // Quoting is for libiberty's response parser; no shell interprets these bytes.
        ByteArray response;
        for (const Utf8& argument : arguments)
        {
            response.append("\"");
            for (char character : argument.view())
            {
                if (character == '\\' || character == '"')
                    response.pushBack(std::byte{'\\'});
                response.pushBack(static_cast<std::byte>(character));
            }
            response.append("\"\n");
        }
        const fs::path responsePath = directory / "arguments.rsp";
        if (!writeBytes(job, responsePath, response))
            return false;
        const std::array<Utf8, 1> invocation = {"@" + Utf8(responsePath)};
        std::string output;
        uint32_t exitCode = 0;
        const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false, .timeoutMs = 120000};
        const auto result = Os::runProcess(exitCode, fs::path(tool), invocation, directory, &options);
        if (result != Os::ProcessRunResult::Ok)
            return linkError(job, std::format("cannot run '{}': {}{}", tool, Os::systemError(), output));
        if (exitCode)
            return linkError(job, std::format("'{}' exited with status {}\n{}", tool, exitCode, output));
        return true;
    }

    bool publish(LinkJob& job, const fs::path& generated, const fs::path& destination, bool archive)
    {
        ByteArray bytes;
        FileSystem::IoErrorInfo error;
        if (FileSystem::readBinaryFile(generated, bytes, error) != Result::Continue)
            return linkError(job, FileSystem::describeIoFailure(error));
        const bool valid = archive ? bytes.size() >= 8 && std::memcmp(bytes.data(), "!<arch>\n", 8) == 0 :
                                     bytes.size() >= 64 && bytes.readLe32(0) == 0x464c457f && bytes[4] == std::byte{2} && bytes[5] == std::byte{1} && bytes.readLe16(18) == 62;
        if (!valid)
            return linkError(job, "the GNU toolchain did not produce the requested ELF64 artifact");
        Utf8 symbolError;
        if (!archive && !ELFSymbolTable::finalizeImage(bytes, symbolError))
            return linkError(job, symbolError.view());
        const auto replacement = archive ? FileSystem::FileReplacement::Mapped : FileSystem::FileReplacement::Ordinary;
        if (FileSystem::writeBinaryFileAtomic(destination, bytes.data(), bytes.size(), error, replacement) != Result::Continue)
            return linkError(job, FileSystem::describeIoFailure(error));
        if (!archive)
        {
            std::error_code permissionsError;
            fs::permissions(destination, fs::perms::owner_exec | fs::perms::group_exec | fs::perms::others_exec, fs::perm_options::add, permissionsError);
            if (permissionsError)
                return linkError(job, permissionsError.message());
        }
        return true;
    }

    bool materialize(std::vector<Utf8>& paths, LinkJob& job, const std::vector<LinkArchiveMember>& objects, const fs::path& directory)
    {
        std::error_code error;
        fs::create_directories(directory, error);
        if (error)
            return linkError(job, error.message());
        for (const LinkArchiveMember& object : objects)
        {
            const fs::path path = directory / fs::path(object.name.c_str()).filename();
            if (!writeBytes(job, path, object.bytes))
                return false;
            // Tools run in the parent directory. Short relative operands avoid GNU ar's
            // expensive comparisons of the shared absolute prefix in large member lists.
            paths.emplace_back(path.lexically_relative(directory.parent_path()));
        }
        return true;
    }

    bool executePrepared(LinkJob& job)
    {
        static std::atomic<uint64_t> nextId{0};
        const fs::path temporary = job.buildDir / std::format("elf-link-{}-{}", Os::currentProcessId(), nextId.fetch_add(1, std::memory_order_relaxed));
        struct RemoveTemporary
        {
            fs::path path;
            ~RemoveTemporary() { std::error_code error; fs::remove_all(path, error); }
        } cleanup{temporary};
        std::vector<Utf8> objects;
        if (!materialize(objects, job, job.archiveMembers, temporary / "objects"))
            return false;
        const fs::path output = temporary / job.outputPath.filename();
        if (job.output == LinkJob::Output::StaticLibrary)
        {
            std::vector<Utf8> arguments = {"rcsD", Utf8(output)};
            arguments.insert(arguments.end(), objects.begin(), objects.end());
            if (!runTool(job, "ar", arguments, temporary) || !publish(job, output, job.outputPath, true))
                return false;
        }
        else
        {
            // Lazy ELF resolution preserves System V arguments, but Swag also passes arguments
            // in R10/R11. Resolve PLT entries before the first call can lose those registers.
            std::vector<Utf8> arguments = {"-Wl,--build-id=none", "-Wl,-z,noexecstack", "-Wl,-z,relro", "-Wl,-z,now", "-Wl,--eh-frame-hdr", "-Wl,--fatal-warnings", "-pthread"};
            if (job.output == LinkJob::Output::Executable)
                arguments.emplace_back("-no-pie");
            else
            {
                arguments.emplace_back("-shared");
                arguments.emplace_back("-Wl,-Bsymbolic");
                arguments.emplace_back("-Wl,-z,text");
                arguments.emplace_back("-Wl,-soname," + Utf8(job.outputPath.filename()));
            }
            arguments.emplace_back("-Wl,-rpath,$ORIGIN");
            arguments.insert(arguments.end(), objects.begin(), objects.end());
            arguments.insert(arguments.end(), job.elfLinkArguments.begin(), job.elfLinkArguments.end());
            arguments.emplace_back("-o");
            arguments.emplace_back(output);
            if (!runTool(job, "cc", arguments, temporary) || !publish(job, output, job.outputPath, false))
                return false;
        }
        if (!job.staticLibraryPath.empty())
        {
            std::vector<Utf8> members;
            if (!materialize(members, job, job.staticLibraryMembers, temporary / "archive"))
                return false;
            const fs::path archive = temporary / "companion.a";
            std::vector<Utf8> arguments = {"rcsD", Utf8(archive)};
            arguments.insert(arguments.end(), members.begin(), members.end());
            if (!runTool(job, "ar", arguments, temporary) || !publish(job, archive, job.staticLibraryPath, true))
                return false;
        }
        return true;
    }
}

Result ELFLinker::prepareLink(LinkJob& outJob)
{
    outJob            = {};
    outJob.targetOs   = Runtime::TargetOs::Linux;
    outJob.outputPath = fs::absolute(builder_->artifactPath);
    outJob.buildDir   = fs::absolute(builder_->buildDir);
    const auto kind   = builder_->compiler().buildCfg().backendKind;
    outJob.output     = kind == Runtime::BuildCfgBackendKind::StaticLibrary ? LinkJob::Output::StaticLibrary : kind == Runtime::BuildCfgBackendKind::SharedLibrary ? LinkJob::Output::SharedLibrary
                                                                                                                                                                   : LinkJob::Output::Executable;
    if (kind != Runtime::BuildCfgBackendKind::StaticLibrary)
        SWC_RESULT(builder_->buildObjectBytes());
    takeObjects(outJob.archiveMembers, *builder_);
    for (const NativeFunctionInfo& info : builder_->functionInfos)
    {
        if (!info.cacheHit)
            continue;
        const NativeFunctionCacheRecord* record = builder_->functionCacheRecord(*info.symbol);
        SWC_ASSERT(record && record->hit);
        outJob.archiveMembers.push_back({.name = std::format("cached_function_{:06}.o", outJob.archiveMembers.size()), .bytes = record->objectBytes});
    }
    if (kind == Runtime::BuildCfgBackendKind::SharedLibrary)
    {
        const Utf8 scope = nativeArtifactScopeName(builder_->compiler());
        outJob.elfLinkArguments.emplace_back("-Wl,--defsym," + Utf8(K_SHARED_RUNTIME_HOOK_SYMBOL) + "=" + runtimeHookSymbolName(scope.view()));
    }

    std::set<Utf8> libraries = {"c", "m", "dl"};
    for (const Utf8& library : builder_->compiler().foreignLibs())
        libraries.insert(library);
    for (const NativeFunctionInfo& function : builder_->functionInfos)
        if (function.machineCode)
            collectLibraries(libraries, builder_->ctx(), *function.machineCode);
    if (builder_->startup)
        collectLibraries(libraries, builder_->ctx(), builder_->startup->code);
    appendLibraryArguments(outJob, builder_->compiler(), libraries);

    if (kind == Runtime::BuildCfgBackendKind::SharedLibrary)
    {
        const NativeArtifactBuilder artifacts(*builder_);
        NativeArtifactPaths         paths;
        artifacts.queryPaths(paths);
        if (!paths.staticLibraryPath.empty())
        {
            SWC_RESULT(artifacts.partitionArchiveObjects());
            SWC_RESULT(builder_->buildObjectBytes());
            takeObjects(outJob.staticLibraryMembers, *builder_);
            outJob.staticLibraryPath = fs::absolute(paths.staticLibraryPath);
        }
    }
    const CompilerInstance& compiler = builder_->compiler();
    if (kind == Runtime::BuildCfgBackendKind::Executable && compiler.hasImportedStaticLinkInputs() &&
        compiler.cmdLine().command != CommandKind::Test && !compiler.buildCfg().backend.debugInfo && !compiler.importedNativeExecuted())
    {
        // Preserve exactly the objects used by this link, including function-cache hits.
        // One checksummed generation avoids mixing objects from interrupted publications.
        ByteArray bytes;
        if (buildRelinkCache(bytes, outJob.archiveMembers))
        {
            const fs::path path = outJob.buildDir / (Utf8(outJob.outputPath.filename()) + ".relink.elfcache").c_str();
            outJob.incrementalObjects.push_back({.path = path, .bytes = std::move(bytes)});
            outJob.incrementalLibraries.assign(libraries.begin(), libraries.end());
        }
    }
    return prepareFunctionCache(outJob);
}

Result ELFLinker::prepareFunctionCache(LinkJob& job) const
{
    if (!builder_->functionCacheEnabled())
        return Result::Continue;
    const NativeArtifactBuilder artifacts(*builder_);
    SWC_RESULT(artifacts.partitionIncrementalFunctionObjects());
    SWC_RESULT(builder_->buildObjectBytes());

    std::unordered_map<const SymbolFunction*, const ByteArray*> generated;
    for (const NativeObjDescription& object : builder_->objectDescriptions)
    {
        SWC_ASSERT(object.functions.size() == 1);
        generated.emplace(object.functions.front()->symbol, &object.objBytes);
    }
    std::vector<NativeElfCachedFunction> entries;
    for (const NativeFunctionInfo& info : builder_->functionInfos)
    {
        const NativeFunctionCacheRecord* record = builder_->functionCacheRecord(*info.symbol);
        if (!record)
            continue;
        const ByteArray* bytes = record->hit ? &record->objectBytes : nullptr;
        if (!bytes)
        {
            const auto found = generated.find(info.symbol);
            if (found != generated.end())
                bytes = found->second;
        }
        if (!bytes || !isSelfContainedElfObject(bytes->span(), info.symbolName.view()))
            continue;
        entries.push_back({.key = record->key.view(), .fingerprint = record->fingerprint.view(), .symbolName = info.symbolName.view(), .callClobbers = info.symbol->callClobbers(), .objectBytes = bytes->span()});
    }
    ByteArray bytes;
    if (NativeElfFunctionCache(compilerCacheIdentity()).build(bytes, entries))
        job.incrementalCacheFiles.push_back({.path = builder_->functionCacheArchivePath(), .bytes = std::move(bytes)});
    return Result::Continue;
}

Result ELFLinker::tryPrepareIncrementalLink(bool& outPrepared, LinkJob& outJob, const std::span<const fs::path> objectPaths, const std::span<const Utf8> libraryNames)
{
    outPrepared                      = false;
    const CompilerInstance& compiler = builder_->compiler();
    if (objectPaths.size() != 1 || compiler.buildCfg().backendKind != Runtime::BuildCfgBackendKind::Executable ||
        compiler.cmdLine().command == CommandKind::Test || compiler.buildCfg().backend.debugInfo || compiler.importedNativeExecuted())
        return Result::Continue;

    ByteArray                      bytes;
    FileSystem::IoErrorInfo        error;
    std::vector<LinkArchiveMember> objects;
    if (FileSystem::readBinaryFile(objectPaths.front(), bytes, error) != Result::Continue || !readRelinkCache(objects, bytes))
        return Result::Continue;

    outJob                = {};
    outJob.targetOs       = Runtime::TargetOs::Linux;
    outJob.output         = LinkJob::Output::Executable;
    outJob.outputPath     = fs::absolute(builder_->artifactPath);
    outJob.buildDir       = fs::absolute(builder_->buildDir);
    outJob.archiveMembers = std::move(objects);
    // The manifest owns API freshness; dependency paths are resolved again against
    // this invocation's selected artifacts, never replayed from an old command line.
    std::set<Utf8> libraries(libraryNames.begin(), libraryNames.end());
    for (const Utf8& library : compiler.foreignLibs())
        libraries.insert(library);
    appendLibraryArguments(outJob, compiler, libraries);
    outPrepared = true;
    return Result::Continue;
}

void ELFLinker::execute(LinkJob& job)
{
    job.ok = executePrepared(job);
}

SWC_END_NAMESPACE();
