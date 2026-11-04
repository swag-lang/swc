#include "pch.h"
#include "Backend/Linker/Linker.elf.h"
#include "Backend/Linker/ObjectWriter.elf.h"
#include "Backend/Linker/ELFImageWriter.h"
#include "Backend/Linker/SymbolTable.elf.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeFunctionCache.elf.h"
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
                const fs::path  candidate = directory / (name.string() + std::string(extension));
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

    void collectLibraryInputs(LinkJob& job, const CompilerInstance& compiler, const std::set<Utf8>& libraries)
    {
        std::set<fs::path> archives;
        for (const fs::path& directory : compiler.importedDependencyLinkDirs())
        {
            job.elfSearchDirs.push_back(fs::absolute(directory));
            std::error_code error;
            for (fs::directory_iterator it(directory, fs::directory_options::skip_permission_denied, error), end; it != end && !error; it.increment(error))
            {
                if (it->is_regular_file(error) && it->path().extension() == ".a")
                    archives.insert(fs::absolute(it->path()));
            }
        }
        for (const fs::path& archive : archives)
            job.elfLibraries.push_back(archive);
        for (const Utf8& library : libraries)
        {
            const fs::path name(library.c_str());
            if (name.has_parent_path())
                job.elfLibraries.push_back(fs::absolute(name));
            else
            {
                const fs::path dependency = resolveDependencyLibrary(name, compiler.importedDependencyLinkDirs());
                if (!dependency.empty())
                {
                    if (!archives.contains(dependency))
                        job.elfLibraries.push_back(dependency);
                }
                else
                    job.elfLibraries.push_back(name);
            }
        }
    }

    bool linkError(LinkJob& job, std::string_view reason)
    {
        job.error = Diagnostic::get(DiagnosticId::cmd_err_link_external_failed);
        job.error.addArgument(Diagnostic::ARG_PATH, Utf8(job.outputPath));
        job.error.addArgument(Diagnostic::ARG_BECAUSE, Utf8(reason));
        return false;
    }

    bool publishImage(LinkJob& job)
    {
        ByteArray bytes;
        Utf8 error;
        if (!buildElfImage(bytes, error, job) || !ELFSymbolTable::finalizeImage(bytes, error))
            return linkError(job, error.view());
        FileSystem::IoErrorInfo io;
        if (FileSystem::writeBinaryFileAtomic(job.outputPath, bytes.data(), bytes.size(), io, FileSystem::FileReplacement::Ordinary) != Result::Continue)
            return linkError(job, FileSystem::describeIoFailure(io));
        std::error_code permissionsError;
        fs::permissions(job.outputPath, fs::perms::owner_exec | fs::perms::group_exec | fs::perms::others_exec, fs::perm_options::add, permissionsError);
        if (permissionsError)
            return linkError(job, permissionsError.message());
        return true;
    }

    bool publishArchive(LinkJob& job, const std::vector<LinkArchiveMember>& members, const fs::path& destination)
    {
        ByteArray bytes;
        if (!buildElfStaticArchive(bytes, job.error, members))
            return false;
        FileSystem::IoErrorInfo error;
        if (FileSystem::writeBinaryFileAtomic(destination, bytes.data(), bytes.size(), error, FileSystem::FileReplacement::Mapped) != Result::Continue)
            return linkError(job, FileSystem::describeIoFailure(error));
        return true;
    }

    bool executePrepared(LinkJob& job)
    {
        if (job.output == LinkJob::Output::StaticLibrary)
        {
            if (!publishArchive(job, job.archiveMembers, job.outputPath))
                return false;
        }
        else if (!publishImage(job))
            return false;
        if (!job.staticLibraryPath.empty())
        {
            if (!publishArchive(job, job.staticLibraryMembers, job.staticLibraryPath))
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
        outJob.elfRuntimeHook = runtimeHookSymbolName(scope.view());
    }

    std::set<Utf8> libraries = {"c", "m", "dl"};
    for (const Utf8& library : builder_->compiler().foreignLibs())
        libraries.insert(library);
    for (const NativeFunctionInfo& function : builder_->functionInfos)
        if (function.machineCode)
            collectLibraries(libraries, builder_->ctx(), *function.machineCode);
    if (builder_->startup)
        collectLibraries(libraries, builder_->ctx(), builder_->startup->code);
    collectLibraryInputs(outJob, builder_->compiler(), libraries);

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
    collectLibraryInputs(outJob, compiler, libraries);
    outPrepared = true;
    return Result::Continue;
}

void ELFLinker::execute(LinkJob& job)
{
    job.ok = executePrepared(job);
}

SWC_END_NAMESPACE();
