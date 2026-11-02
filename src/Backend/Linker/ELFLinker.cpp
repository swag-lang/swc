#include "pch.h"
#include "Backend/Linker/ELFLinker.h"
#include "Backend/Linker/ELFSymbolTable.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeNames.h"
#include "Backend/RuntimeName.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"

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
            std::vector<Utf8> arguments = {"-Wl,--build-id=none", "-Wl,-z,noexecstack", "-Wl,-z,relro", "-Wl,--eh-frame-hdr", "-Wl,--fatal-warnings", "-pthread"};
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
    outJob = {};
    outJob.targetOs = Runtime::TargetOs::Linux;
    outJob.outputPath = fs::absolute(builder_->artifactPath);
    outJob.buildDir = fs::absolute(builder_->buildDir);
    const auto kind = builder_->compiler().buildCfg().backendKind;
    outJob.output = kind == Runtime::BuildCfgBackendKind::StaticLibrary ? LinkJob::Output::StaticLibrary :
                   kind == Runtime::BuildCfgBackendKind::SharedLibrary ? LinkJob::Output::SharedLibrary : LinkJob::Output::Executable;
    if (kind != Runtime::BuildCfgBackendKind::StaticLibrary)
        SWC_RESULT(builder_->buildObjectBytes());
    takeObjects(outJob.archiveMembers, *builder_);
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
    std::set<fs::path> archives;
    for (const fs::path& directory : builder_->compiler().importedDependencyLinkDirs())
    {
        outJob.elfLinkArguments.emplace_back("-L" + Utf8(fs::absolute(directory)));
        // -L does not resolve DT_NEEDED entries of imported shared libraries. Keep this
        // search path link-only so deployed artifacts retain their $ORIGIN runpath.
        outJob.elfLinkArguments.emplace_back("-Xlinker");
        outJob.elfLinkArguments.emplace_back("-rpath-link");
        outJob.elfLinkArguments.emplace_back("-Xlinker");
        outJob.elfLinkArguments.emplace_back(Utf8(fs::absolute(directory)));
        std::error_code error;
        for (fs::directory_iterator it(directory, fs::directory_options::skip_permission_denied, error), end; it != end && !error; it.increment(error))
        {
            if (it->is_regular_file(error) && it->path().extension() == ".a")
                archives.insert(fs::absolute(it->path()));
        }
    }
    outJob.elfLinkArguments.emplace_back("-Wl,--start-group");
    for (const fs::path& archive : archives)
        outJob.elfLinkArguments.emplace_back(archive);
    for (const Utf8& library : libraries)
    {
        const fs::path name(library.c_str());
        if (name.has_parent_path())
            outJob.elfLinkArguments.emplace_back(fs::absolute(name));
        else
        {
            const fs::path dependency = resolveDependencyLibrary(name, builder_->compiler().importedDependencyLinkDirs());
            if (!dependency.empty())
            {
                if (!archives.contains(dependency))
                    outJob.elfLinkArguments.emplace_back(dependency);
            }
            else if (name.has_extension())
                outJob.elfLinkArguments.emplace_back("-l:" + library);
            else
                outJob.elfLinkArguments.emplace_back("-l" + library);
        }
    }
    outJob.elfLinkArguments.emplace_back("-Wl,--end-group");

    if (kind == Runtime::BuildCfgBackendKind::SharedLibrary)
    {
        const NativeArtifactBuilder artifacts(*builder_);
        NativeArtifactPaths paths;
        artifacts.queryPaths(paths);
        if (!paths.staticLibraryPath.empty())
        {
            SWC_RESULT(artifacts.partitionArchiveObjects());
            SWC_RESULT(builder_->buildObjectBytes());
            takeObjects(outJob.staticLibraryMembers, *builder_);
            outJob.staticLibraryPath = fs::absolute(paths.staticLibraryPath);
        }
    }
    return Result::Continue;
}

Result ELFLinker::tryPrepareIncrementalLink(bool& outPrepared, LinkJob&, std::span<const fs::path>, std::span<const Utf8>)
{
    // Persistent native relinks currently store COFF archives. Linux rebuilds its ELF
    // objects until the cache has a target-specific object/index reader.
    outPrepared = false;
    return Result::Continue;
}

void ELFLinker::execute(LinkJob& job)
{
    job.ok = executePrepared(job);
}

SWC_END_NAMESPACE();
