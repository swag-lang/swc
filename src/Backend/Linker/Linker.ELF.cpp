#include "pch.h"
#include "Backend/Linker/Linker.ELF.h"
#include "Backend/Linker/ImageWriter.ELF.h"
#include "Backend/Linker/ObjectWriter.ELF.h"
#include "Backend/Linker/SymbolTable.ELF.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeFunctionCache.ELF.h"
#include "Backend/Native/NativeNames.h"
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

    void collectLibraries(std::set<Utf8>& libraries, const MachineCode& code)
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
                name = function->foreignModuleName();
            if (!name.empty())
                libraries.insert(std::move(name));
        }
    }

    void collectLibraryInputs(LinkJob& job, const std::set<Utf8>& libraries)
    {
        for (const Utf8& library : libraries)
        {
            const fs::path name(library.c_str());
            job.elfLibraries.push_back(name.has_parent_path() ? fs::absolute(name) : name);
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
        Utf8      error;
        if (!buildElfImage(bytes, error, job) || !ELFSymbolTable::finalizeImage(bytes, error, job.elfRuntimeSymbols))
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

}

Result ELFLinker::prepareLink(LinkJob& outJob)
{
    outJob                   = {};
    outJob.targetOs          = Runtime::TargetOs::Linux;
    outJob.outputPath        = fs::absolute(builder_->artifactPath);
    outJob.buildDir          = fs::absolute(builder_->buildDir);
    outJob.elfStripSymbols   = !builder_->compiler().buildCfg().backend.debugInfo;
    outJob.elfRuntimeSymbols = !builder_->compiler().cmdLine().noRuntimeSymbols;
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
    std::set<Utf8> libraries = {"c", "m", "dl"};
    for (const Utf8& library : builder_->compiler().foreignLibs())
        libraries.insert(library);
    for (const NativeFunctionInfo& function : builder_->functionInfos)
        if (function.machineCode)
            collectLibraries(libraries, *function.machineCode);
    if (builder_->startup)
        collectLibraries(libraries, builder_->startup->code);
    collectLibraryInputs(outJob, libraries);
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

void ELFLinker::execute(LinkJob& job)
{
    job.ok = publishImage(job);
}

SWC_END_NAMESPACE();
