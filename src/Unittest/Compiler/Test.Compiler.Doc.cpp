#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Runtime.h"
#include "Doc/DocGenerator.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/Stats.h"
#include "Support/Os/Os.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class ScopedDocTestDirectory
    {
    public:
        explicit ScopedDocTestDirectory(const std::string_view testName)
        {
            root_ = (Os::getTemporaryPath() / "swc_unittest" / "doc" / std::format("{}_p{}", testName, Os::currentProcessId())).lexically_normal();

            std::error_code ec;
            fs::remove_all(root_, ec);
            ec.clear();
            const bool created = fs::create_directories(root_, ec);
            ready_             = !ec && (created || fs::exists(root_));
        }

        ~ScopedDocTestDirectory()
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

    Runtime::String runtimeString(const std::string_view value)
    {
        return {
            .ptr    = value.data(),
            .length = value.size(),
        };
    }
}

SWC_TEST_BEGIN(Compiler_DocCommandParsesOptions)
{
    CommandLine parserCmdLine;
    char        arg0[] = "swc_devmode";
    char        arg1[] = "doc";
    char        arg2[] = "--css";
    char        arg3[] = "site.css";
    char        arg4[] = "--no-output-doc";
    char        arg5[] = "--doc-output-dir";
    char        arg6[] = "generated-doc";
    char*       argv[] = {arg0, arg1, arg2, arg3, arg4, arg5, arg6};

    CommandLineParser parser(const_cast<Global&>(ctx.global()), parserCmdLine);
    if (parser.parse(std::size(argv), argv) != Result::Continue)
        return Result::Error;

    if (parserCmdLine.command != CommandKind::Doc)
        return Result::Error;
    if (parserCmdLine.docCss != "site.css")
        return Result::Error;
    if (parserCmdLine.outputDoc)
        return Result::Error;
    if (parserCmdLine.docOutputDir.filename() != "generated-doc")
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_DocMarkdownRendersSupportedBlocks)
{
    static constexpr std::string_view SOURCE = R"(# Heading

| Name | Meaning |
|---|---|
| value | A value |

> NOTE: Read this.

```swag
const value = 1
```
)";

    const Utf8 html = DocGenerator::renderMarkdownForTest(ctx, SOURCE);
    if (!html.contains("<h1 id=\"Heading\">Heading</h1>"))
        return Result::Error;
    if (!html.contains("<table class=\"table-markdown\">"))
        return Result::Error;
    if (!html.contains("blockquote-note"))
        return Result::Error;
    if (!html.contains("class=\"code-block\""))
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Compiler_DocGeneratesPublicApiAndHonorsNoDoc)
{
    // The first declaration deliberately omits the blank comment line so this test
    // also proves that a malformed long description cannot flood summary tables.
    static constexpr std::string_view SOURCE      = R"(#global namespace DocApi
#global public

// Returns the next integer.
// The long description belongs only to the standalone symbol documentation.
func documented(value: s32)->s32
{
    return value + 1
}

// Source-order summary for an overloaded function.
func ordered(value: s32) {}
func ordered(value: f32) {}

// A small public value used to verify methods and anonymous storage.
//
// ## Example
//
// ```swag
// var counter: Counter
// ```
struct Counter
{
    value: s32           // Current counter value.
    next:  #null *Counter // Optional next counter in a caller-owned chain.

    using storage: union // Active numeric storage.
    {
        integer: s32
        decimal: f32
    }
}

impl Counter
{
    // Increase the counter by one.
    mtd increment()
    {
        .value += 1
    }
}

// A value whose state can be reset.
interface Resettable
{
    // Reset the value to zero.
    mtd reset()
}

impl Resettable for Counter
{
    mtd impl reset()
    {
        .value = 0
    }
}

// A packed public coordinate.
#[Swag.Pack(1)]
struct PackedCoordinate
{
    x: u8
}

// Selects a test mode.
enum TestMode
{
    Fast = 41 // Prefer lower latency.
    Full // Prefer complete coverage.
}

#[Swag.Opaque]
// An opaque public record.
struct OpaqueRecord
{
    implementationValue: u64
}

// A record whose implementation state is restricted.
struct RestrictedRecord
{
    publicValue: u64 // Part of the API.

    // Read from anywhere, written only by the type: still part of the API.
    readonly observedValue: u64

    internal moduleValue: u64 // Restricted to the module.
    private  ownedValue:  u64 // Restricted to the type.
}

// Keep this compiler-only helper out of the API page.
#[Swag.NoDoc]
func hidden(value: s32)->s32
{
    return value
}
)";
    static constexpr std::string_view OUTPUT_NAME = "doc-test";
    static constexpr std::string_view TITLE       = "Documentation Test";

    ScopedDocTestDirectory directory("public-api");
    if (!directory.ready())
        return Result::Error;

    const fs::path sourcePath = Unittest::makeTestSourcePath("Compiler", "DocGeneratesPublicApiAndHonorsNoDoc");

    CommandLine cmdLine;
    cmdLine.command      = CommandKind::Doc;
    cmdLine.name         = "compiler_doc_test";
    cmdLine.docOutputDir = directory.root();
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    Runtime::BuildCfgGenDoc& genDoc = compiler.buildCfg().genDoc;
    genDoc.kind                     = Runtime::BuildCfgDocKind::Api;
    genDoc.outputName               = runtimeString(OUTPUT_NAME);
    genDoc.titleContent             = runtimeString(TITLE);

    TaskContext                  compilerCtx(compiler);
    DocGenerator::GenerateResult generated;
    const DocGenerator           generator(compilerCtx);
    SWC_RESULT(generator.generate(generated));

    const fs::path          outputPath = directory.root() / "doc-test.html";
    std::string             content;
    FileSystem::IoErrorInfo ioError;
    SWC_RESULT(FileSystem::readTextFile(outputPath, content, ioError));
    if (!content.contains("documented") || !content.contains("Returns the next integer.") || !content.contains("The long description belongs only to the standalone symbol documentation."))
        return Result::Error;
    const size_t documentedSummary = content.find("href=\"#Compiler_doc_test_DocApi_documented\"");
    const size_t documentedRowEnd  = content.find("</tr>", documentedSummary);
    const size_t documentedDetail  = content.find("The long description belongs only to the standalone symbol documentation.");
    if (documentedSummary == std::string::npos || documentedRowEnd == std::string::npos || documentedDetail == std::string::npos || documentedDetail < documentedRowEnd)
        return Result::Error;
    if (!content.contains("id=\"Counter_increment\"") || !content.contains("Increase the counter by one."))
        return Result::Error;
    if (!content.contains("id=\"Compiler_doc_test_DocApi_Resettable_reset\"") || !content.contains("Reset the value to zero."))
        return Result::Error;
    if (content.contains("Counter.Resettable.reset"))
        return Result::Error;
    if (!content.contains("<p>A packed public coordinate.</p>"))
        return Result::Error;
    if (!content.contains("<h3>Cases</h3>") || !content.contains("Prefer lower latency."))
        return Result::Error;
    if (content.contains(">41<"))
        return Result::Error;
    if (!content.contains("href=\"#Compiler_doc_test_DocApi_Counter\">Counter</a>"))
        return Result::Error;
    if (!content.contains("id=\"namespace_Compiler_doc_test_DocApi\"") || !content.contains("Public API declared directly in"))
        return Result::Error;
    const size_t counterItem    = content.find("id=\"Compiler_doc_test_DocApi_Counter\"");
    const size_t counterSummary = content.find("id=\"Compiler_doc_test_DocApi_Counter_methods\"", counterItem);
    const size_t counterMethod  = content.find("id=\"Counter_increment\"");
    const size_t opaqueItem     = content.find("id=\"Compiler_doc_test_DocApi_OpaqueRecord\"");
    if (counterItem == std::string::npos || counterSummary == std::string::npos || counterMethod == std::string::npos || opaqueItem == std::string::npos || counterSummary < counterItem || counterSummary > opaqueItem || counterMethod < opaqueItem)
        return Result::Error;
    if (content.contains("api-method-details") || !content.contains("Counter.increment"))
        return Result::Error;
    if (content.contains(">implementationValue<"))
        return Result::Error;

    // A field restricted to its module or its type is not API, so it stays off the page; a
    // read-only field is API for reading, so it stays on it.
    if (content.contains(">moduleValue<") || content.contains(">ownedValue<"))
        return Result::Error;
    if (!content.contains(">publicValue<") || !content.contains(">observedValue<"))
        return Result::Error;
    if (content.contains("id=\"Example\"") || !content.contains("Compiler_doc_test_DocApi_Counter_0_Example"))
        return Result::Error;
    if (content.contains("__anonymous_"))
        return Result::Error;
    if (!content.contains("<p>Active numeric storage.</p>"))
        return Result::Error;
    if (content.contains(">hidden<") || content.contains("func hidden"))
        return Result::Error;
    const size_t orderedItem    = content.find("id=\"Compiler_doc_test_DocApi_ordered\"");
    const size_t orderedSummary = content.find("<p>Source-order summary for an overloaded function.</p>", orderedItem);
    const size_t orderedCode    = content.find("<div class=\"code-block\"", orderedItem);
    const size_t nextItem       = content.find("<table class=\"api-item\"", orderedItem + 1);
    if (orderedItem == std::string::npos || orderedSummary == std::string::npos || orderedCode == std::string::npos || orderedSummary > orderedCode || (nextItem != std::string::npos && orderedCode > nextItem))
        return Result::Error;
    if (!content.contains("<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\">"))
        return Result::Error;
    if (content.contains("<script") || content.contains("<?php"))
        return Result::Error;

    const fs::path stylesheetPath = directory.root() / "style.css";
    SWC_RESULT(FileSystem::readTextFile(stylesheetPath, content, ioError));
    if (!content.contains(".site-header") || !content.contains(".code-block"))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
