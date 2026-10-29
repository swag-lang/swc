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
        {"FoldedPrivateConstant", R"(#global public
private const Hidden = 42
#[Swag.Inline]
func exposed()->s32 => Hidden
)",
         "symbol 'Hidden' is not exposed by the module API",
         {},
         "static-library",
         "discard exposed()"},
        {"FoldedQualifiedConstant", R"(#global public
namespace Inner { private const Hidden = 42'u8 }
#[Swag.Inline]
func exposed(value: s32)->s32 => value + Inner.Hidden
)",
         "is not exposed by the module API"},
        {"FoldedPublicConstant", R"(#global public
const Visible = 42
#[Swag.Inline]
func exposed()->s32 => Visible
)",
         {},
         "=> Visible",
         "static-library",
         "discard exposed()"},
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
        {"ImplicitReceiver", R"(#global public
struct Value { value = 42 }
impl Value
{
    #[Swag.Inline]
    mtd read()->s32 => me.value
    #[Swag.Inline]
    mtd exposed()->s32 => .read()
}
)",
         {},
         "=> .read()",
         "static-library",
         "var value: Value\n    discard value.exposed()"},
        {"Intrinsic", R"(#global public
#[Swag.Inline]
func exposed()->*Swag.Context => Swag.getContext()
)",
         {},
         "=> Swag.getContext()",
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
func exposed(value: *s32)->s32 => Swag.atomicAdd(value, 1)
)",
         {},
         "=> Swag.atomicAdd(value, 1)",
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
        SWC_RESULT(CompilerTestFile::writeText(consumer, std::format("using InlineApi\n#main\n{{\n    {}\n}}\n", test.use)));
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

SWC_FILESYSTEM_TEST_BEGIN(ModuleApi_ImplicitBodyExportContract)
{
    ApiPublicationTestDirectory directory("ImplicitBodies");
    for (const std::string_view access : {"private", "internal", "public"})
    {
        const fs::path    module = directory.path() / access;
        const fs::path    api    = module / "api";
        const std::string source = std::format(R"(#global public
struct Value {{ public amount: s32 }}
impl Value
{{
    {} mtd const positive()->bool => .amount > 0
    #[Swag.Implicit]
    mtd opSet(amount: s32)
    {{
        if .positive() do
            .amount = 0
        .amount = amount
    }}
}}
)",
                                               access);
        SWC_RESULT(CompilerTestFile::writeText(module / "module.swg", "#run {}\n"));
        SWC_RESULT(CompilerTestFile::writeText(module / "src" / "provider.swg", source));
        const std::vector<Utf8> args = {"sema", "--module", Utf8(module.string()), "--module-namespace", "ImplicitApi", "--artifact-kind", "static-library", "--export-api-dir", Utf8(api.string()), "--num-cores", "6"};
        ImportResult            result;
        Os::ProcessRunOptions   options;
        options.capturedOutput = &result.output;
        options.forwardOutput  = false;
        options.timeoutMs      = 15000;
        result.process         = Os::runProcess(result.exitCode, Os::getExeFullName(), args, module, &options);
        const bool exported    = access == "public";
        if (result.process != Os::ProcessRunResult::Ok || (result.exitCode == 0) != exported)
        {
            std::println(stderr, "[implicit API {}] {}", access, result.output);
            return Result::Error;
        }
        if (!exported)
        {
            if (result.output.find("cannot export the body of implicit function '") == std::string::npos ||
                result.output.find("is not exposed by the module API") == std::string::npos ||
                result.output.find("keep the operation in the published body") == std::string::npos ||
                result.output.find("referenced symbol '") == std::string::npos)
                return Result::Error;
            continue;
        }

        const fs::path consumer = module / "consumer.swg";
        SWC_RESULT(CompilerTestFile::writeText(consumer, "using ImplicitApi\n#main { var value: Value = 42\n discard value }\n"));
        const fs::path          apiFile    = api / (std::string(access) + ".swg");
        const std::vector<Utf8> importArgs = {"sema", "--num-cores", "6", "-f", Utf8(consumer.string()), "--import-api-file", Utf8(apiFile.string())};
        result.output.clear();
        result.process = Os::runProcess(result.exitCode, Os::getExeFullName(), importArgs, module, &options);
        if (result.process != Os::ProcessRunResult::Ok || result.exitCode != 0)
        {
            std::println(stderr, "[implicit API consumer] {}", result.output);
            return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(ModuleApi_PublishesSupportingDeclarations)
{
    ApiPublicationTestDirectory directory("SupportingDecls");
    struct Case
    {
        std::string_view name;
        std::string_view source;
        std::string_view use;
        // Fragments the generated interface must carry, or of the export error when it cannot.
        std::vector<std::string_view> published;
        std::vector<std::string_view> because;
        std::string_view              helperFile;
    };
    const Case cases[] = {
        {"PrivateHelper", R"(#global public
private func helper(value: s32)->s32 => value + 1
func(T) exposed(value: T)->s32 => helper(cast(s32, value))
)",
         "discard exposed(41)",
         {"private func helper(value: s32)->s32 => value + 1"}},
        {"TransitiveHelpers", R"(#global public
private func inner(value: s32)->s32 => value * 2
private func outer(value: s32)->s32 => inner(value) + 1
func(T) exposed(value: T)->s32 => outer(cast(s32, value))
)",
         "discard exposed(20)",
         {"private func inner(value: s32)->s32 => value * 2", "private func outer(value: s32)->s32 => inner(value) + 1"}},
        {"QualifiedHelper", R"(#global public
namespace Inner { private func helper(value: s32)->s32 => value + 1 }
func(T) exposed(value: T)->s32 => Inner.helper(cast(s32, value))
)",
         "discard exposed(41)",
         {"private func helper(value: s32)->s32 => value + 1"}},
        {"InternalMethod", R"(#global public
struct Reader { public value: s32 }
impl Reader
{
    internal mtd bump() { .value += 1 }
    mtd(T) read()->T
    {
        .bump()
        return cast(T, .value)
    }
}
)",
         "var reader: Reader\n    discard reader.read's32()",
         {"internal mtd bump() { .value += 1 }"}},
        {"PrivateTypeAndConstant", R"(#global public
private const Scale = 3
private struct Pair { a: s32, b: s32 }
func(T) exposed(value: T)->s32
{
    var pair: Pair
    pair.a = cast(s32, value) * Scale
    return pair.a + pair.b
}
)",
         "discard exposed(2)",
         {"private const Scale = 3", "private struct Pair { a: s32, b: s32 }"}},
        {"OtherFileHelper", R"(#global public
func(T) exposed(value: T)->s32 => helper(cast(s32, value))
)",
         "discard exposed(41)",
         {"internal func helper(value: s32)->s32 => value + 1"},
         {},
         "internal func helper(value: s32)->s32 => value + 1\n"},
        {"HelperReadsGlobal", R"(#global public
private var counter: s32 = 0
private func helper(value: s32)->s32 => value + counter
func(T) exposed(value: T)->s32 => helper(cast(s32, value))
)",
         "discard exposed(41)",
         {},
         {"cannot export non-public function 'helper', which a published generic body needs", "symbol 'counter' is not exposed by the module API", "export the referenced implementation too"}},
        {"InternalFieldType", R"(#global public
private struct Slot { a: s32 }
struct Holder
{
    slot:   Slot
    public value: s32
}
)",
         "var holder: Holder\n    holder.value = 1",
         {"private struct Slot { a: s32 }"}},
        {"InternalFieldAlias", R"(#global public
private alias Handle = const *void?
struct Holder
{
    handle: Handle
    public value: s32
}
)",
         "var holder: Holder\n    holder.value = 1",
         {"private alias Handle = const *void?"}},
        {"InternalFieldAnonymousType", R"(#global public
private struct Slot { a: s32 }
struct Holder
{
    pair:   { first: Slot, second: s32 }
    public value: s32
}
)",
         "var holder: Holder\n    holder.value = 1",
         {"private struct Slot { a: s32 }"}},
        {"InternalFieldNamesGlobal", R"(#global public
private var counter: s32 = 0
struct Holder
{
    slot:   #decltype(counter)
    public value: s32
}
)",
         "",
         {},
         {"cannot export internal field 'slot' of public struct", "symbol 'counter' is not exposed by the module API"}},
        {"InternalFieldTypeChain", R"(#global public
private const Empty = 7
private struct Inner { a: s32 = Empty }
private struct Outer { inner: Inner }
struct Holder
{
    outer:  [2] Outer
    public value: s32
}
)",
         "var holder: Holder\n    holder.value = 1",
         {"private const Empty = 7", "private struct Inner { a: s32 = Empty }", "private struct Outer { inner: Inner }"}},
        {"PublicFieldOfInternalType", R"(#global public
private struct Slot { a: s32 }
struct Holder { public slot: Slot }
)",
         "",
         {},
         {"cannot export public struct 'Holder' because field 'slot' uses non-public type"}},
        {"PublicFieldForeignGenericOfInternalType", R"(#global public
private struct Slot { a: s32 }
struct Holder { public slot: Swag.AtomicValue'Slot }
)",
         "",
         {},
         {"cannot export public struct 'Holder' because field 'slot' uses non-public type"}},
    };

    for (const Case& test : cases)
    {
        const fs::path module = directory.path() / test.name;
        const fs::path api    = module / "api";
        SWC_RESULT(CompilerTestFile::writeText(module / "module.swg", "#run {}\n"));
        SWC_RESULT(CompilerTestFile::writeText(module / "src" / "provider.swg", test.source));
        if (!test.helperFile.empty())
            SWC_RESULT(CompilerTestFile::writeText(module / "src" / "helper.swg", test.helperFile));

        const std::vector<Utf8> args = {"sema", "--module", Utf8(module.string()), "--module-namespace", "GenericApi", "--artifact-kind", "static-library", "--export-api-dir", Utf8(api.string()), "--num-cores", "6"};
        ImportResult            result;
        Os::ProcessRunOptions   options;
        options.capturedOutput = &result.output;
        options.forwardOutput  = false;
        options.timeoutMs      = 15000;
        result.process         = Os::runProcess(result.exitCode, Os::getExeFullName(), args, module, &options);
        if (result.process != Os::ProcessRunResult::Ok || (result.exitCode == 0) != test.because.empty())
        {
            std::println(stderr, "[supporting API {}] {}", test.name, result.output);
            return Result::Error;
        }

        if (!test.because.empty())
        {
            for (const std::string_view fragment : test.because)
            {
                if (result.output.find(fragment) == std::string::npos)
                {
                    std::println(stderr, "[supporting API {}] {}", test.name, result.output);
                    return Result::Error;
                }
            }
            continue;
        }

        std::string             generated;
        FileSystem::IoErrorInfo ioError;
        const fs::path          apiFile = api / (std::string(test.name) + ".swg");
        if (FileSystem::readTextFile(apiFile, generated, ioError) != Result::Continue)
        {
            std::println(stderr, "[supporting API {}] cannot read '{}'", test.name, apiFile.string());
            return Result::Error;
        }
        for (const std::string_view fragment : test.published)
        {
            if (generated.find(fragment) == std::string::npos)
            {
                std::println(stderr, "[supporting API {}] missing '{}' in:\n{}", test.name, fragment, generated);
                return Result::Error;
            }
        }

        const fs::path consumer = module / "consumer.swg";
        SWC_RESULT(CompilerTestFile::writeText(consumer, std::format("using GenericApi\n#main\n{{\n    {}\n}}\n", test.use)));
        const std::vector<Utf8> importArgs = {"sema", "--num-cores", "6", "-f", Utf8(consumer.string()), "--import-api-file", Utf8(apiFile.string())};
        result.output.clear();
        result.process = Os::runProcess(result.exitCode, Os::getExeFullName(), importArgs, module, &options);
        if (result.process != Os::ProcessRunResult::Ok || result.exitCode != 0)
        {
            std::println(stderr, "[supporting API consumer {}] {}", test.name, result.output);
            return Result::Error;
        }
    }
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(ModuleApi_WholeFileBodyExportContract)
{
    ApiPublicationTestDirectory directory("WholeFileBodies");
    const fs::path              api = directory.path() / "api";
    SWC_RESULT(CompilerTestFile::writeText(directory.path() / "module.swg", "#run {}\n"));
    SWC_RESULT(CompilerTestFile::writeText(directory.path() / "src" / "provider.swg", "#global export\nfunc exposed(value: s32)->s32 => helper(value)\n"));
    const fs::path helper = directory.path() / "src" / "helper.swg";
    SWC_RESULT(CompilerTestFile::writeText(helper, "internal func helper(value: s32)->s32 => value + 1\n"));

    const std::vector<Utf8> args = {"sema", "--module", Utf8(directory.path().string()), "--module-namespace", "WholeApi", "--artifact-kind", "static-library", "--export-api-dir", Utf8(api.string()), "--num-cores", "6"};
    ImportResult            result;
    Os::ProcessRunOptions   options;
    options.capturedOutput = &result.output;
    options.forwardOutput  = false;
    options.timeoutMs      = 15000;
    result.process         = Os::runProcess(result.exitCode, Os::getExeFullName(), args, directory.path(), &options);
    if (result.process != Os::ProcessRunResult::Ok || result.exitCode == 0 ||
        result.output.find("cannot export the body of function 'WholeApi.exposed'") == std::string::npos ||
        result.output.find("symbol 'WholeApi.helper' is not exposed by the module API") == std::string::npos ||
        result.output.find("referenced symbol 'WholeApi.helper' is declared here") == std::string::npos ||
        result.output.find("helper.swg:1:") == std::string::npos ||
        result.output.find("use '#global public' to publish declarations") == std::string::npos)
    {
        std::println(stderr, "[whole-file API rejection] {}", result.output);
        return Result::Error;
    }

    // An internal dependency can stay internal when its source travels with the API.
    SWC_RESULT(CompilerTestFile::writeText(helper, "#global export\ninternal func helper(value: s32)->s32 => value + 1\n"));
    result.output.clear();
    result.process = Os::runProcess(result.exitCode, Os::getExeFullName(), args, directory.path(), &options);
    if (result.process != Os::ProcessRunResult::Ok || result.exitCode != 0)
    {
        std::println(stderr, "[whole-file API dependency] {}", result.output);
        return Result::Error;
    }

    const fs::path consumer = directory.path() / "consumer.swg";
    SWC_RESULT(CompilerTestFile::writeText(consumer, "#main { Swag.assert(WholeApi.exposed(41) == 42) }\n"));
    const std::vector<Utf8> importArgs = {"sema", "--num-cores", "6", "-f", Utf8(consumer.string()), "--import-api-file", Utf8((api / "provider.swg").string()), "--import-api-file", Utf8((api / "helper.swg").string())};
    result.output.clear();
    result.process = Os::runProcess(result.exitCode, Os::getExeFullName(), importArgs, directory.path(), &options);
    if (result.process != Os::ProcessRunResult::Ok || result.exitCode != 0)
    {
        std::println(stderr, "[whole-file API consumer] {}", result.output);
        return Result::Error;
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
        std::vector<char8_t> bytes;
        SWC_RESULT(FileSystem::readBinaryFile(file.path, bytes, ioError, SourceContent::TRAILING_0));
        file.content = std::make_shared<const SourceContent>(std::move(bytes));
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
        if (content != file.content->view() || fs::last_write_time(path, ec) != file.writeTime || ec)
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
    const std::vector<ModuleApi::SourceSnapshot> files  = {{.path = source / "value.swg", .content = std::make_shared<const SourceContent>(API_SOURCE), .writeTime = writeTime}};
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

#ifdef _WIN32
SWC_FILESYSTEM_TEST_BEGIN(Workspace_LocalFunctionDoesNotOverrideNativeImport)
{
    ApiPublicationTestDirectory directory("LocalForeignCollision");
    constexpr std::string_view  providerSetup  = R"(#run
{
    with let cfg = unwrap Swag.compiler().getBuildCfg()
    {
        .moduleNamespace = "Provider"
        .backendKind = .StaticLibrary
    }
}
)";
    constexpr std::string_view  providerSource = R"(#global export
func host()->s32
{
    func send(_: u64, _: const [*] u8?, _: s32, _: s32)->s32 => 99
    return send(0, null, 0, 0)
}
)";
    constexpr std::string_view  consumerSetup  = R"(#import("provider")
#run { Swag.compiler().getBuildCfg()!.backendKind = .Executable }
)";
    constexpr std::string_view  consumerSource = R"(#foreignlib("ws2_32")
#[Foreign("ws2_32", callconv: Swag.CallConv.C)]
func send(socket: u64, buffer: const [*] u8?, length, flags: s32)->s32
#main
{
    Swag.assert(Provider.host() == 99)
    Swag.assert(send(Swag.U64.Max, null, 0, 0) == -1)
}
)";
    const fs::path              modules        = directory.path() / "modules";
    SWC_RESULT(CompilerTestFile::writeText(modules / "provider" / "module.swg", providerSetup));
    SWC_RESULT(CompilerTestFile::writeText(modules / "provider" / "src" / "provider.swg", providerSource));
    SWC_RESULT(CompilerTestFile::writeText(modules / "consumer" / "module.swg", consumerSetup));
    SWC_RESULT(CompilerTestFile::writeText(modules / "consumer" / "src" / "consumer.swg", consumerSource));

    const std::vector<Utf8> arguments = {"build", "--workspace", Utf8(directory.path()), "--workspace-module", "consumer", "--rebuild", "--num-cores", "6"};
    Os::ProcessRunOptions   options;
    std::string             output;
    options.capturedOutput = &output;
    options.forwardOutput  = false;
    options.timeoutMs      = 30000;
    uint32_t exitCode      = UINT32_MAX;
    if (Os::runProcess(exitCode, Os::getExeFullName(), arguments, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode != 0)
    {
        std::println(stderr, "cannot build the local/foreign collision reproducer:\n{}", output);
        return Result::Error;
    }

    const fs::path executable = directory.path() / ".output" / "consumer" / "executable" / "devmode" / "x86_64" / "consumer.exe";
    output.clear();
    if (Os::runProcess(exitCode, executable, {}, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode != 0)
    {
        std::println(stderr, "the native import was not resolved independently of the local function:\n{}", output);
        return Result::Error;
    }
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Workspace_ParsesDependentBeforeJoiningItsDependencyLink)
{
    ApiPublicationTestDirectory directory("WorkspaceParseBeforeLink");
    constexpr std::string_view  providerSetup  = R"(#run
{
    with let cfg = unwrap Swag.compiler().getBuildCfg()
    {
        .moduleNamespace = "Provider"
        .backendKind = .SharedLibrary
    }
}
)";
    constexpr std::string_view  consumerSetup  = R"(#import("provider")
#run
{
    with let cfg = unwrap Swag.compiler().getBuildCfg()
    {
        .moduleNamespace = "Consumer"
        .backendKind = .SharedLibrary
    }
}
)";
    const fs::path              modules        = directory.path() / "modules";
    const fs::path              consumerSource = modules / "consumer" / "src" / "broken.swg";
    SWC_RESULT(CompilerTestFile::writeText(modules / "provider" / "module.swg", providerSetup));
    SWC_RESULT(CompilerTestFile::writeText(modules / "provider" / "src" / "value.swg", "#global public\nfunc value()->s32 => 42\n"));
    SWC_RESULT(CompilerTestFile::writeText(modules / "consumer" / "module.swg", consumerSetup));
    SWC_RESULT(CompilerTestFile::writeText(consumerSource, "#global public\nfunc value()->s32 => Provider.value()\n"));

    const std::vector<Utf8> arguments = {"build", "--workspace", Utf8(directory.path()), "--workspace-module", "consumer", "--rebuild", "--num-cores", "6"};
    Os::ProcessRunOptions   options;
    std::string             output;
    options.capturedOutput = &output;
    options.forwardOutput  = false;
    options.timeoutMs      = 15000;
    uint32_t exitCode      = UINT32_MAX;
    if (Os::runProcess(exitCode, Os::getExeFullName(), arguments, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode)
    {
        std::println(stderr, "workspace seed did not build:\n{}", output);
        return Result::Error;
    }

    // The CRT reader denies deletion on Windows. Hold the previous DLL in place
    // until the child's link has exhausted its publication retries: a serial
    // dependency join then fails before the consumer's parser can run.
    const fs::path library = directory.path() / ".output" / "provider" / "shared-library" / "devmode" / "x86_64" / "provider.dll";
    std::ifstream  lockedLibrary(library, std::ios::binary);
    if (!lockedLibrary.is_open())
        return Result::Error;
    SWC_RESULT(CompilerTestFile::writeText(consumerSource, "func broken() { let = 1 }\n"));
    output.clear();
    exitCode = UINT32_MAX;
    if (Os::runProcess(exitCode, Os::getExeFullName(), arguments, directory.path(), &options) != Os::ProcessRunResult::Ok || !exitCode)
        return Result::Error;
    if (output.find("broken.swg") == std::string::npos)
    {
        std::println(stderr, "dependent source was not parsed before the dependency link:\n{}", output);
        return Result::Error;
    }
}
SWC_TEST_END()
#endif

SWC_END_NAMESPACE();

#endif
