#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/ModuleApi/ModuleApi.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class ApiPublicationTestDirectory
    {
    public:
        explicit ApiPublicationTestDirectory(const std::string_view name)
        {
            path_ = (Os::getTemporaryPath() / "swc_unittest" / "api_publication" / std::format("{}_p{}", name, Os::currentProcessId())).lexically_normal();
            std::error_code ec;
            fs::remove_all(path_, ec);
        }

        ~ApiPublicationTestDirectory()
        {
            std::error_code ec;
            fs::remove_all(path_, ec);
        }

        const fs::path& path() const { return path_; }
        fs::path        apiDirectory() const { return path_ / "dep" / "export" / "devmode" / "x86_64"; }

    private:
        fs::path path_;
    };

    Result writePublicationSource(const fs::path& path, const std::string_view text)
    {
        std::error_code ec;
        fs::create_directories(path.parent_path(), ec);
        if (ec)
            return Result::Error;
        FileSystem::IoErrorInfo error;
        return FileSystem::writeBinaryFile(path, text.data(), text.size(), error);
    }

    struct ImportResult
    {
        Os::ProcessRunResult process  = Os::ProcessRunResult::StartFailed;
        uint32_t             exitCode = UINT32_MAX;
        std::string          output;
    };

    void runPublicationImporter(ImportResult& result, const ApiPublicationTestDirectory& directory)
    {
        const std::vector<Utf8> args = {"sema", "--num-cores", "6", "-f", Utf8((directory.path() / "consumer.swg").string()), "--import-api-file", Utf8((directory.apiDirectory() / "value.swg").string())};
        Os::ProcessRunOptions   options;
        options.capturedOutput = &result.output;
        options.forwardOutput  = false;
        options.timeoutMs      = 15000;
        result.process         = Os::runProcess(result.exitCode, Os::getExeFullName(), args, directory.path(), &options);
    }

    Result loadScriptCachedApi(fs::path& outPath, std::string& outContent, const TaskContext& ctx, const fs::path& script)
    {
        CommandLine command;
        command.command        = CommandKind::Sema;
        command.scriptMode     = true;
        command.silent         = true;
        command.numCores       = 6;
        command.moduleFilePath = script;
        command.files.insert(script);
        CommandLineParser::refreshBuildCfg(command);

        CompilerInstance compiler(ctx.global(), command);
        TaskContext      importCtx(compiler);
        SWC_RESULT(compiler.runModuleSetup(importCtx));
        for (const SourceFile* file : compiler.files())
        {
            if (!file->hasFlag(FileFlagsE::ImportedApi) || file->path().filename() != "value.swg")
                continue;
            outPath = file->path();
            FileSystem::IoErrorInfo ioError;
            return FileSystem::readTextFile(outPath, outContent, ioError);
        }
        return Result::Error;
    }

    constexpr std::string_view API_SOURCE      = "#global public\nconst PublicationValue = 42\n";
    constexpr std::string_view CONSUMER_SOURCE = "#test\n{\n    const value: s32 = PublicationValue\n}\n";
}

SWC_FILESYSTEM_TEST_BEGIN(ModuleApi_IncompletePublicationIsRejectedAndCanBeRebuilt)
{
    ApiPublicationTestDirectory directory("Incomplete");
    SWC_RESULT(writePublicationSource(directory.path() / "consumer.swg", CONSUMER_SOURCE));
    SWC_RESULT(writePublicationSource(directory.apiDirectory() / "value.swg", API_SOURCE));

    Utf8 because;
    {
        // Leaving without completePublication models a failed or terminated exporter. Even a
        // syntactically valid subset is unusable: the missing files may contain declarations.
        ModuleApi::DirectoryAccess publication;
        SWC_RESULT(publication.beginPublication(because, directory.apiDirectory()));
    }

    ImportResult incomplete;
    runPublicationImporter(incomplete, directory);
    if (incomplete.process != Os::ProcessRunResult::Ok || incomplete.exitCode == 0)
        return Result::Error;
    if (incomplete.output.find("module API publication did not complete") == std::string::npos)
        return Result::Error;

    {
        ModuleApi::DirectoryAccess publication;
        SWC_RESULT(publication.beginPublication(because, directory.apiDirectory()));
        SWC_RESULT(publication.completePublication(because));
    }
    ImportResult complete;
    runPublicationImporter(complete, directory);
    if (complete.process != Os::ProcessRunResult::Ok || complete.exitCode != 0)
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(ModuleApi_ImporterWaitsForCompletePublication)
{
    ApiPublicationTestDirectory directory("Concurrent");
    SWC_RESULT(writePublicationSource(directory.path() / "consumer.swg", CONSUMER_SOURCE));
    SWC_RESULT(writePublicationSource(directory.apiDirectory() / "value.swg", "this API is still being written\n"));

    ImportResult      importer;
    std::atomic<bool> finished = false;
    std::thread       reader;
    std::barrier      started(2);
    bool              returnedBeforePublication = false;
    Result            writeResult               = Result::Continue;
    {
        ModuleApi::DirectoryAccess publication;
        Utf8                       because;
        SWC_RESULT(publication.beginPublication(because, directory.apiDirectory()));
        reader = std::thread([&] {
            started.arrive_and_wait();
            runPublicationImporter(importer, directory);
            finished.store(true, std::memory_order_release);
        });
        started.arrive_and_wait();
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        returnedBeforePublication = finished.load(std::memory_order_acquire);
        writeResult               = writePublicationSource(directory.apiDirectory() / "value.swg", API_SOURCE);
        if (writeResult == Result::Continue)
            writeResult = publication.completePublication(because);
    }
    reader.join();
    if (writeResult != Result::Continue || returnedBeforePublication || importer.process != Os::ProcessRunResult::Ok || importer.exitCode != 0)
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(ModuleApi_RepublishesCapturedSourcesAndMetadata)
{
    ApiPublicationTestDirectory directory("Snapshot");
    const fs::path              source      = directory.apiDirectory();
    const fs::path              destination = directory.path() / "mirror";
    SWC_RESULT(writePublicationSource(source / "value.swg", API_SOURCE));
    SWC_RESULT(writePublicationSource(source / ".swc-deps", "#import(\"dependency\")\n"));
    SWC_RESULT(writePublicationSource(destination / "stale.swg", "obsolete\n"));
    SWC_RESULT(writePublicationSource(destination / "artifact.lib", "retained artifact\n"));

    std::vector<ModuleApi::SourceSnapshot> files;
    FileSystem::IoErrorInfo                ioError;
    std::error_code                        ec;
    for (const char* name : {"value.swg", ".swc-deps"})
    {
        ModuleApi::SourceSnapshot file;
        file.path      = source / name;
        file.writeTime = fs::last_write_time(file.path, ec);
        if (ec)
            return Result::Error;
        SWC_RESULT(FileSystem::readTextFile(file.path, file.content, ioError));
        files.push_back(std::move(file));
    }

    // The source generation can disappear before the destination lock is acquired. A mirror
    // still publishes the complete captured generation, including its dependency metadata.
    fs::remove_all(source, ec);
    if (ec)
        return Result::Error;
    {
        ModuleApi::DirectoryAccess publication;
        Utf8                       because;
        SWC_RESULT(publication.beginPublication(because, destination));
        SWC_RESULT(ModuleApi::writeSnapshot(ctx, files, source, destination));
        SWC_RESULT(publication.completePublication(because));
    }

    for (const ModuleApi::SourceSnapshot& file : files)
    {
        const fs::path path = destination / file.path.filename();
        std::string    content;
        SWC_RESULT(FileSystem::readTextFile(path, content, ioError));
        if (content != file.content || fs::last_write_time(path, ec) != file.writeTime || ec)
            return Result::Error;
    }
    if (fs::exists(destination / "stale.swg") || !fs::exists(destination / "artifact.lib"))
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(ModuleApi_SnapshotReplacesEqualSizeAndTimestampContents)
{
    ApiPublicationTestDirectory directory("SnapshotSameMetadata");
    const fs::path              destination = directory.apiDirectory();
    const fs::path              path        = destination / "value.swg";
    constexpr std::string_view  oldContent  = "#global public\nconst PublicationValue = 41\n";
    static_assert(oldContent.size() == API_SOURCE.size());
    SWC_RESULT(writePublicationSource(path, oldContent));

    std::error_code ec;
    const auto      writeTime = fs::last_write_time(path, ec);
    if (ec)
        return Result::Error;

    // Restoring a source tree can preserve both size and timestamp while changing its API.
    // Publishing the captured bytes must replace a mirror from that previous generation.
    const fs::path                               source = directory.path() / "source";
    const std::vector<ModuleApi::SourceSnapshot> files  = {{.path = source / "value.swg", .content = std::string(API_SOURCE), .writeTime = writeTime}};
    {
        ModuleApi::DirectoryAccess publication;
        Utf8                       because;
        SWC_RESULT(publication.beginPublication(because, destination));
        SWC_RESULT(ModuleApi::writeSnapshot(ctx, files, source, destination));
        SWC_RESULT(publication.completePublication(because));
    }

    std::string             content;
    FileSystem::IoErrorInfo ioError;
    SWC_RESULT(FileSystem::readTextFile(path, content, ioError));
    if (content != API_SOURCE || fs::last_write_time(path, ec) != writeTime || ec)
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(ModuleApi_ScriptCacheDistinguishesEqualSizeAndTimestampContents)
{
    ApiPublicationTestDirectory directory("ScriptCacheSameMetadata");
    const fs::path              source = directory.apiDirectory() / "value.swg";
    const fs::path              script = directory.path() / "consumer.swgs";
    SWC_RESULT(writePublicationSource(source, API_SOURCE));
    SWC_RESULT(writePublicationSource(script, "#import(\"dep\", location: \".\")\n#main {}\n"));

    std::error_code ec;
    const auto      writeTime = fs::last_write_time(source, ec);
    if (ec)
        return Result::Error;
    fs::path    firstPath;
    std::string firstContent;
    SWC_RESULT(loadScriptCachedApi(firstPath, firstContent, ctx, script));
    if (firstPath == source || firstContent != API_SOURCE)
        return Result::Error;

    constexpr std::string_view newContent = "#global public\nconst PublicationValue = 43\n";
    static_assert(newContent.size() == API_SOURCE.size());
    {
        ModuleApi::DirectoryAccess publication;
        Utf8                       because;
        SWC_RESULT(publication.beginPublication(because, directory.apiDirectory()));
        SWC_RESULT(writePublicationSource(source, newContent));
        fs::last_write_time(source, writeTime, ec);
        if (ec)
            return Result::Error;
        SWC_RESULT(publication.completePublication(because));
    }

    // The cache file itself must match the new capture. Importing from the fresh in-memory
    // snapshot alone would hide reuse of an obsolete on-disk cache generation.
    fs::path    secondPath;
    std::string secondContent;
    SWC_RESULT(loadScriptCachedApi(secondPath, secondContent, ctx, script));
    if (secondPath == firstPath || secondContent != newContent)
        return Result::Error;
    FileSystem::IoErrorInfo ioError;
    SWC_RESULT(FileSystem::readTextFile(firstPath, firstContent, ioError));
    if (firstContent != API_SOURCE)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
