#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Runtime.h"
#include "Compiler/Doc/DocGenerator.h"
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
    static constexpr std::string_view SOURCE      = R"(#global public

// Return the next integer.
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
    value: s32 // Current counter value.

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
    Fast // Prefer lower latency.
    Full // Prefer complete coverage.
}

#[Swag.Opaque]
// An opaque public record.
struct OpaqueRecord
{
    implementationValue: u64
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
    if (!content.contains("documented") || !content.contains("Return the next integer."))
        return Result::Error;
    if (!content.contains("Counter.increment") || !content.contains("Increase the counter by one."))
        return Result::Error;
    if (!content.contains("Resettable.reset") || !content.contains("Reset the value to zero."))
        return Result::Error;
    if (content.contains("Counter.Resettable.reset"))
        return Result::Error;
    if (!content.contains("<p>A packed public coordinate.</p>"))
        return Result::Error;
    if (!content.contains("<h3>Values</h3>") || !content.contains("Prefer lower latency."))
        return Result::Error;
    if (content.contains(">implementationValue<"))
        return Result::Error;
    if (content.contains("id=\"Example\"") || !content.contains("Counter_0_Example"))
        return Result::Error;
    if (content.contains("__anonymous_"))
        return Result::Error;
    if (!content.contains("<p>Active numeric storage.</p>"))
        return Result::Error;
    if (content.contains(">hidden<") || content.contains("func hidden"))
        return Result::Error;
    const size_t orderedSummary = content.find("<p>Source-order summary for an overloaded function.</p>");
    const size_t orderedItem    = content.rfind("<table class=\"api-item\"", orderedSummary);
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
