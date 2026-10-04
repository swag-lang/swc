#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/ModuleApi/ModuleApi.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"
#include "Unittest/Compiler/CompilerTestFile.h"
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
        command.modulePath     = script.parent_path();
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
    SWC_RESULT(CompilerTestFile::writeText(directory.path() / "consumer.swg", CONSUMER_SOURCE));
    SWC_RESULT(CompilerTestFile::writeText(directory.apiDirectory() / "value.swg", API_SOURCE));

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

SWC_FILESYSTEM_TEST_BEGIN(ModuleApi_NamedStandardImportUsesWorkspaceOutputRoot)
{
    ApiPublicationTestDirectory directory("NamedStandardImport");
    const fs::path              compilerPath = directory.path() / Os::getExeFullName().filename();
    const fs::path              runtimePath  = directory.path() / "runtime";
    const fs::path              apiPath      = directory.path() / "std" / ".output" / "health_import" / "export" / "devmode" / "x86_64";

    std::error_code ec;
    fs::create_directories(runtimePath, ec);
    if (ec)
        return Result::Error;
    fs::copy_file(Os::getExeFullName(), compilerPath, ec);
    if (ec)
        return Result::Error;

    // A private compiler/resource tree tests the actual CLI without publishing anything
    // into the checkout's standard-library outputs or changing process-wide environment.
    const fs::path sourceRuntime = FileSystem::compilerResourceRoot(Os::getExeFullName()) / "runtime";
    for (const auto& entry : fs::directory_iterator(sourceRuntime, ec))
    {
        if (!entry.is_regular_file() || entry.path().extension() != ".swg")
            continue;
        fs::copy_file(entry.path(), runtimePath / entry.path().filename(), ec);
        if (ec)
            return Result::Error;
    }
    if (ec)
        return Result::Error;

    SWC_RESULT(CompilerTestFile::writeText(directory.path() / "consumer.swg", CONSUMER_SOURCE));
    fs::create_directories(apiPath, ec);
    if (ec)
        return Result::Error;
    {
        Utf8                       because;
        ModuleApi::DirectoryAccess publication;
        SWC_RESULT(publication.beginPublication(because, apiPath));
        SWC_RESULT(CompilerTestFile::writeText(apiPath / "value.swg", API_SOURCE));
        SWC_RESULT(publication.completePublication(because));
    }

    const std::vector<Utf8> args = {"sema", "--num-cores", "6", "-f", Utf8((directory.path() / "consumer.swg").string()), "--import-api-module", "health_import"};
    ImportResult            result;
    Os::ProcessRunOptions   options;
    options.capturedOutput = &result.output;
    options.forwardOutput  = false;
    options.timeoutMs      = 15000;
    result.process         = Os::runProcess(result.exitCode, compilerPath, args, directory.path(), &options);
    if (result.process != Os::ProcessRunResult::Ok || result.exitCode != 0)
    {
        std::println(stderr, "[named standard import] {}", result.output);
        return Result::Error;
    }
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(ModuleApi_AnalyzesImportedFunctionBodiesOnDemand)
{
    ApiPublicationTestDirectory directory("LazyBodies");
    constexpr std::string_view  apiSource       = R"(#global public
struct ImportedValue
{
    public value: s32
}
impl ImportedValue
{
    mtd read()->s32 => .value
}
func importedValue()->s32 => 42
func importedFailure()->s32 => MissingImportedBodySymbol
)";
    constexpr std::string_view  validConsumer   = R"(#main
{
    const value = importedValue()
    Swag.assert(value == 42)
    var imported: ImportedValue
    imported.value = value
    Swag.assert(imported.read() == 42)
}
)";
    constexpr std::string_view  invalidConsumer = R"(#main
{
    discard importedFailure()
}
)";

    SWC_RESULT(CompilerTestFile::writeText(directory.apiDirectory() / "value.swg", apiSource));
    SWC_RESULT(CompilerTestFile::writeText(directory.path() / "consumer.swg", validConsumer));

    ImportResult unusedInvalidBody;
    runPublicationImporter(unusedInvalidBody, directory);
    if (unusedInvalidBody.process != Os::ProcessRunResult::Ok || unusedInvalidBody.exitCode != 0)
        return Result::Error;

    SWC_RESULT(CompilerTestFile::writeText(directory.path() / "consumer.swg", invalidConsumer));
    ImportResult usedInvalidBody;
    runPublicationImporter(usedInvalidBody, directory);
    if (usedInvalidBody.process != Os::ProcessRunResult::Ok || usedInvalidBody.exitCode == 0)
        return Result::Error;
    if (usedInvalidBody.output.find("MissingImportedBodySymbol") == std::string::npos)
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(ModuleApi_InlineBodyExportContract)
{
    ApiPublicationTestDirectory directory("InlineBodies");
    struct Case
    {
        std::string_view name;
        std::string_view source;
        std::string_view because;
        std::string_view inlineBody;
        std::string_view artifactKind = "static-library";
        std::string_view use          = "discard exposed(42)";
    };
    const Case cases[] = {
        {"PrivateHelper", R"(#global public
private func helper(value: s32)->s32 => value + 1
#[Swag.Inline]
func exposed(value: s32)->s32 => helper(value)
)",
         "symbol 'helper' is not exposed by the module API"},
        {"InternalHelper", R"(#global public
internal func helper(value: s32)->s32 => value + 1
#[Swag.Inline]
func exposed(value: s32)->s32 => helper(value)
)",
         "symbol 'InlineApi.helper' is not exposed by the module API"},
        {"PrivateConstant", R"(#global public
private const Hidden: [2] s32 = [41, 42]
#[Swag.Inline]
func exposed(index: u64)->s32 => Hidden[index]
)",
         "symbol 'Hidden' is not exposed by the module API"},
        {"OpaqueMember", R"(#global public
#[Swag.Opaque]
struct Hidden { value: s32 }
impl Hidden
{
    #[Swag.Inline]
    mtd exposed()->s32 => .value
}
)",
         "is not exposed by the module API"},
        {"Intrinsic", R"(#global public
#[Swag.Inline]
func exposed()->*Swag.Context => Swag.getContext()
)",
         {},
         "=> Swag.getContext",
         "static-library",
         "discard exposed()"},
        {"Assertion", R"(#global public
#[Swag.Inline]
func exposed(value: s32)->s32
{
    Swag.assert(value > 0)
    return value
}
)",
         {},
         "Swag.assert(value > 0)"},
        {"Atomic", R"(#global public
#[Swag.Inline]
func exposed(value: *s32)->s32 => Swag.atomadd(value, 1)
)",
         {},
         "=> Swag.atomadd(value, 1)",
         "static-library",
         "var value: s32 = 42\n    discard exposed(&value)"},
        {"PublicHelper", R"(#global public
func helper(value: s32)->s32 => value + 1
#[Swag.Inline]
func exposed(value: s32)->s32 => helper(value)
)",
         {},
         "=> helper(value)"},
        {"QualifiedHelper", R"(#global public
namespace Nested { func helper(value: s32)->s32 => value + 1 }
#[Swag.Inline]
func exposed(value: s32)->s32 => Nested.helper(value)
)",
         {},
         "=> Nested.helper(value)"},
        {"PublicOverload", R"(#global public
private func helper(value: f32)->f32 => value + 1
func helper(value: s32)->s32 => value + 1
#[Swag.Inline]
func exposed(value: s32)->s32 => helper(value)
)",
         {},
         "=> helper(value)"},
        {"NoInline", R"(#global public
private func helper(value: s32)->s32 => value + 1
func exposed(value: s32)->s32 => helper(value)
)",
         {}},
        {"PrivateInline", R"(#global public
#[Swag.Inline]
private func helper(value: s32)->s32 => value + 1
func exposed(value: s32)->s32 => helper(value)
)",
         {}},
        {"SourceApi", R"(#global public
private func helper(value: s32)->s32 => value + 1
#[Swag.Inline]
func exposed(value: s32)->s32 => helper(value)
)",
         "symbol 'helper' is not exposed by the module API",
         {},
         "export"},
        {"WholeFile", R"(#global export
private func helper(value: s32)->s32 => value + 1
#[Swag.Inline]
func exposed(value: s32)->s32 => helper(value)
)",
         {},
         "=> helper(value)"},
    };

    for (const Case& test : cases)
    {
        const fs::path module = directory.path() / test.name;
        const fs::path api    = module / "api";
        SWC_RESULT(CompilerTestFile::writeText(module / "module.swg", "#run {}\n"));
        SWC_RESULT(CompilerTestFile::writeText(module / "src" / "provider.swg", test.source));
        const std::vector<Utf8> args = {"sema", "--module", Utf8(module.string()), "--module-namespace", "InlineApi", "--artifact-kind", Utf8(test.artifactKind), "--export-api-dir", Utf8(api.string()), "--num-cores", "6"};
        ImportResult            result;
        Os::ProcessRunOptions   options;
        options.capturedOutput = &result.output;
        options.forwardOutput  = false;
        options.timeoutMs      = 15000;
        result.process         = Os::runProcess(result.exitCode, Os::getExeFullName(), args, module, &options);
        if (result.process != Os::ProcessRunResult::Ok || (result.exitCode == 0) != test.because.empty())
        {
            std::println(stderr, "[inline API {}] {}", test.name, result.output);
            return Result::Error;
        }

        if (!test.because.empty())
        {
            if (result.output.find("cannot export the body of inline function '") == std::string::npos ||
                result.output.find(test.because) == std::string::npos ||
                result.output.find("remove 'Swag.Inline' or make the function body exportable") == std::string::npos)
            {
                std::println(stderr, "[inline API {}] {}", test.name, result.output);
                return Result::Error;
            }
            continue;
        }

        std::string             generated;
        FileSystem::IoErrorInfo ioError;
        const fs::path          apiFile = api / (test.name == "WholeFile" ? "provider.swg" : std::string(test.name) + ".swg");
        if (FileSystem::readTextFile(apiFile, generated, ioError) != Result::Continue)
        {
            std::println(stderr, "[inline API {}] cannot read '{}'", test.name, apiFile.string());
            return Result::Error;
        }
        if ((generated.find("Swag.Inline") != std::string::npos) != !test.inlineBody.empty() ||
            (!test.inlineBody.empty() && generated.find(test.inlineBody) == std::string::npos))
        {
            std::println(stderr, "[inline API {}] {}", test.name, generated);
            return Result::Error;
        }

        const fs::path consumer = module / "consumer.swg";
        SWC_RESULT(CompilerTestFile::writeText(consumer, std::format("using InlineApi\n#test\n{{\n    {}\n}}\n", test.use)));
        const std::vector<Utf8> importArgs = {"sema", "--num-cores", "6", "-f", Utf8(consumer.string()), "--import-api-file", Utf8(apiFile.string())};
        result.output.clear();
        result.process = Os::runProcess(result.exitCode, Os::getExeFullName(), importArgs, module, &options);
        if (result.process != Os::ProcessRunResult::Ok || result.exitCode != 0)
        {
            std::println(stderr, "[inline API consumer {}] {}", test.name, result.output);
            return Result::Error;
        }
    }
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(ModuleApi_ImporterWaitsForCompletePublication)
{
    ApiPublicationTestDirectory directory("Concurrent");
    SWC_RESULT(CompilerTestFile::writeText(directory.path() / "consumer.swg", CONSUMER_SOURCE));
    SWC_RESULT(CompilerTestFile::writeText(directory.apiDirectory() / "value.swg", "this API is still being written\n"));

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
        writeResult               = CompilerTestFile::writeText(directory.apiDirectory() / "value.swg", API_SOURCE);
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
    SWC_RESULT(CompilerTestFile::writeText(source / "value.swg", API_SOURCE));
    SWC_RESULT(CompilerTestFile::writeText(source / ".swc-deps", "#import(\"dependency\")\n"));
    SWC_RESULT(CompilerTestFile::writeText(destination / "stale.swg", "obsolete\n"));
    SWC_RESULT(CompilerTestFile::writeText(destination / "artifact.lib", "retained artifact\n"));

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
    SWC_RESULT(CompilerTestFile::writeText(path, oldContent));

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
    SWC_RESULT(CompilerTestFile::writeText(source, API_SOURCE));
    SWC_RESULT(CompilerTestFile::writeText(script, "#import(\"dep\", location: \".\")\n#main {}\n"));

    std::error_code ec;
    const auto      writeTime = fs::last_write_time(source, ec);
    if (ec)
        return Result::Error;
    fs::path    firstPath;
    std::string firstContent;
    SWC_RESULT(loadScriptCachedApi(firstPath, firstContent, ctx, script));
    if (!fs::exists(directory.path() / ".tmp" / ".swc-setup-devmode"))
        return Result::Error;
    if (firstPath == source || firstContent != API_SOURCE)
        return Result::Error;

    constexpr std::string_view newContent = "#global public\nconst PublicationValue = 43\n";
    static_assert(newContent.size() == API_SOURCE.size());
    {
        ModuleApi::DirectoryAccess publication;
        Utf8                       because;
        SWC_RESULT(publication.beginPublication(because, directory.apiDirectory()));
        SWC_RESULT(CompilerTestFile::writeText(source, newContent));
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
