#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Runtime.h"
#include "Doc/DocApi.h"
#include "Doc/DocGenerator.h"
#include "Doc/DocMarkdown.h"
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

    size_t countOccurrences(const std::string_view text, const std::string_view needle)
    {
        size_t count = 0;
        for (size_t at = text.find(needle); at != std::string_view::npos; at = text.find(needle, at + needle.size()))
            count++;
        return count;
    }

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
|:---|---:|
| value | A value |

> NOTE: Read this.

```swag

const value = 1

```

```

plain payload

```

```
```
)";

    const Utf8 html = DocGenerator::renderMarkdownForTest(ctx, SOURCE);
    if (!html.contains("<h1 id=\"Heading\">Heading</h1>"))
        return Result::Error;
    if (!html.contains("<table class=\"table-markdown\">"))
        return Result::Error;
    if (!html.contains("<thead>\n<tr><th class=\"align-left\">Name</th><th class=\"align-right\">Meaning</th></tr>"))
        return Result::Error;
    if (!html.contains("<tbody>\n<tr><td class=\"align-left\">value</td><td class=\"align-right\">A value</td></tr>"))
        return Result::Error;
    if (!html.contains("blockquote-note"))
        return Result::Error;
    if (!html.contains("class=\"code-block\""))
        return Result::Error;
    if (!html.contains("<div class=\"code-block\"><span class=\"SCde\">plain payload</span></div>\n"))
        return Result::Error;

    // An empty fenced block carries nothing, so it never reaches the page.
    if (html.contains("<span class=\"SCde\"></span>"))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_DocBlockCommentsPreserveCodeIndentation)
{
    static constexpr std::string_view SOURCE = R"(/*
    Summary.

    ```
    zero
        four
    ```
    */)";

    std::vector<Utf8> lines;
    DocApi::appendNormalizedComment(lines, SOURCE);

    DocRenderContext renderCtx = {.ctx = &ctx};
    const Utf8       html      = DocMarkdown::renderLines(renderCtx, lines);
    if (!html.contains("<div class=\"code-block\"><span class=\"SCde\">zero\n    four</span></div>"))
        return Result::Error;

    static constexpr std::string_view STAR_SOURCE = R"(/**
 * ```
 * zero
 *     four
 * ```
 */)";

    lines.clear();
    DocApi::appendNormalizedComment(lines, STAR_SOURCE);
    const Utf8 starHtml = DocMarkdown::renderLines(renderCtx, lines);
    if (!starHtml.contains("<div class=\"code-block\"><span class=\"SCde\">zero\n    four</span></div>"))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_DocMarkdownRendersCompleteLists)
{
    static constexpr std::string_view SOURCE = R"(- A list item that continues
  on the following source line.
- A parent item:
  - A nested item that also
          continues with aligned prose.
  - Another nested item.
- A final item.

1. A numbered item that continues
   on the following source line.
2. Another numbered item.

- A code parent:
  - A nested code item:
    ```
    payload
    ```

+ 'fmt'
    Selects the output format.
)";

    const Utf8 html = DocGenerator::renderMarkdownForTest(ctx, SOURCE);
    if (!html.contains("<li>A list item that continues on the following source line.</li>"))
        return Result::Error;
    if (!html.contains("<li>A parent item:\n<ul>\n<li>A nested item that also continues with aligned prose.</li>\n<li>Another nested item.</li>\n</ul>\n</li>"))
        return Result::Error;
    if (!html.contains("<ol>\n<li>A numbered item that continues on the following source line.</li>\n<li>Another numbered item.</li>\n</ol>"))
        return Result::Error;
    if (!html.contains("A nested code item:\n<div class=\"code-block\"><span class=\"SCde\">payload</span></div>\n</li>"))
        return Result::Error;
    if (!html.contains(R"(<div class="description-list-title"><p><span class="code-inline">fmt</span></p></div>)"))
        return Result::Error;
    if (!html.contains("<div class=\"description-list-block\">\n<p>Selects the output format.</p>\n</div>"))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_DocMarkdownRendersHeaderlessTableAndNestedInline)
{
    // A pipe run without a separator row is a long-standing Swag spelling for a two column
    // definition table; it stays a table instead of falling back to paragraphs.
    static constexpr std::string_view SOURCE = R"(| pix   | address of the pixel
| index | the pixel index

Swag **does not require `break`** at the end of each case, and see https://swag-lang.org/index.php for more.
)";

    const Utf8 html = DocGenerator::renderMarkdownForTest(ctx, SOURCE);
    if (!html.contains("<table class=\"table-markdown\">"))
        return Result::Error;
    if (html.contains("<thead>") || html.contains("<p>|"))
        return Result::Error;
    if (!html.contains("<tr><td>pix</td><td>address of the pixel</td></tr>"))
        return Result::Error;
    if (!html.contains("<b>does not require <span class=\"code-inline\">break</span></b>"))
        return Result::Error;
    if (!html.contains("<a href=\"https://swag-lang.org/index.php\">https://swag-lang.org/index.php</a>"))
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Compiler_DocExamplesNestTableOfContentsLists)
{
    static constexpr std::string_view SOURCE = R"(/**
## Shared heading
*/
)";

    ScopedDocTestDirectory directory("examples-toc");
    if (!directory.ready())
        return Result::Error;

    const fs::path modulePath  = directory.root() / "module.swg";
    const fs::path chapterPath = directory.root() / "001_000_chapter.swg";
    const fs::path firstPath   = directory.root() / "001_001_first_topic.swg";
    const fs::path secondPath  = directory.root() / "001_002_second_topic.swg";

    CommandLine cmdLine;
    cmdLine.command        = CommandKind::Doc;
    cmdLine.name           = "compiler_doc_examples_test";
    cmdLine.docOutputDir   = directory.root();
    cmdLine.moduleFilePath = modulePath;
    cmdLine.modulePath     = directory.root();
    cmdLine.files.insert(chapterPath);
    cmdLine.files.insert(firstPath);
    cmdLine.files.insert(secondPath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    FileSystem::IoErrorInfo moduleIoError;
    SWC_RESULT(FileSystem::writeBinaryFile(modulePath, nullptr, 0, moduleIoError));

    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, chapterPath, SOURCE);
    Unittest::registerTestSource(compiler, firstPath, SOURCE);
    Unittest::registerTestSource(compiler, secondPath, SOURCE);
    Command::sema(compiler);

    Runtime::BuildCfgGenDoc& genDoc = compiler.buildCfg().genDoc;
    genDoc.kind                     = Runtime::BuildCfgDocKind::Examples;
    genDoc.outputName               = runtimeString("examples-toc");

    TaskContext                  compilerCtx(compiler);
    DocGenerator::GenerateResult generated;
    const DocGenerator           generator(compilerCtx);
    SWC_RESULT(generator.generate(generated));

    std::string             content;
    FileSystem::IoErrorInfo ioError;
    SWC_RESULT(FileSystem::readTextFile(directory.root() / "examples-toc.html", content, ioError));
    if (!content.contains("<li><a href=\"#_001_000_chapter_swg\">Chapter</a>\n<ul>\n<li><a href=\"#_001_001_first_topic_swg\">First Topic</a></li>\n<li><a href=\"#_001_002_second_topic_swg\">Second Topic</a></li>\n</ul>\n</li>"))
        return Result::Error;
    if (!content.contains("id=\"_001_000_chapter_swg_Shared_heading\"") ||
        !content.contains("id=\"_001_001_first_topic_swg_Shared_heading\"") ||
        !content.contains("id=\"_001_002_second_topic_swg_Shared_heading\"") || content.contains("id=\"Shared_heading\""))
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
    public value: s32           // Current counter value.
    public next:  #null *Counter // Optional next counter in a caller-owned chain.

    public using storage: union // Active numeric storage.
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
    public x: u8
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
    public publicValue: u64 // Part of the API.

    // Read from anywhere, written only by the type: still part of the API.
    public readonly observedValue: u64

    internal moduleValue: u64 // Restricted to the module.
    private  ownedValue:  u64 // Restricted to the type.
    defaultValue: u64 // Restricted to the module by the default.
}

// A generic record whose declaration is documented without a concrete instance.
struct(T) GenericBox
{
    public zeta: T // Last field alphabetically.

    // Stored value.
    //
    // ## Semantics
    //
    // The detailed field description remains with its owner.
    public value: T

    public alpha: T // First field alphabetically.
    public readonly
    {
        inWeight: T
        interpolation: T
    }
    #[Swag.NoDoc]
    hiddenByAttribute: T
    #[Swag.NoDoc]
    const SECRET = 1
    private hidden: T
}

impl GenericBox
{
    // Returns the stored value.
    mtd get()->T
    {
        return .value
    }

    #[Swag.NoDoc]
    mtd hiddenMethod() {}
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
    if (!content.contains("id=\"Compiler_doc_test_DocApi_Counter_increment\"") || !content.contains("Increase the counter by one."))
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

    // A namespace can be reopened from several files, so its merged symbol has no canonical
    // declaration site. Rendering it as a runtime item must not expose whichever source happened
    // to finish sema last.
    if (compiler.files().empty())
        return Result::Error;
    DocApiDocument runtimeNamespaceDocument;
    DocItem        runtimeNamespaceItem;
    runtimeNamespaceItem.kind        = DocItemKind::Namespace;
    runtimeNamespaceItem.fullName    = "Compiler_doc_test.DocApi";
    runtimeNamespaceItem.displayName = "Compiler_doc_test.DocApi";
    runtimeNamespaceItem.overloads.push_back({.file = compiler.files().front(), .sourceLine = 1});
    runtimeNamespaceDocument.items.push_back(std::move(runtimeNamespaceItem));
    DocApi::renderApiDocument(compilerCtx, runtimeNamespaceDocument, {}, true);
    const size_t namespaceItemStart = runtimeNamespaceDocument.content.find("<div class=\"api-item api-item-namespace\">");
    const size_t namespaceItemEnd   = runtimeNamespaceDocument.content.find("</div>", namespaceItemStart);
    if (namespaceItemStart == std::string_view::npos || namespaceItemEnd == std::string_view::npos ||
        runtimeNamespaceDocument.content.find("api-item-title-src-ref", namespaceItemStart) < namespaceItemEnd)
        return Result::Error;

    const size_t counterItem    = content.find("id=\"Compiler_doc_test_DocApi_Counter\"");
    const size_t counterSummary = content.find("id=\"Compiler_doc_test_DocApi_Counter_methods\"", counterItem);
    const size_t counterMethod  = content.find("id=\"Compiler_doc_test_DocApi_Counter_increment\"");
    const size_t opaqueItem     = content.find("id=\"Compiler_doc_test_DocApi_OpaqueRecord\"");
    if (counterItem == std::string::npos || counterSummary == std::string::npos || counterMethod == std::string::npos || opaqueItem == std::string::npos || counterSummary < counterItem || counterSummary > opaqueItem || counterMethod < opaqueItem)
        return Result::Error;
    if (content.contains("api-method-details") || !content.contains("Counter.increment"))
        return Result::Error;
    if (content.contains(">implementationValue<"))
        return Result::Error;

    // A field restricted to its module or its type is not API, so it stays off the page, and a
    // field that says nothing is restricted by the default; a read-only field is API for reading,
    // so it stays on it.
    if (content.contains(">moduleValue<") || content.contains(">ownedValue<") || content.contains(">defaultValue<"))
        return Result::Error;
    if (!content.contains(">publicValue<") || !content.contains(">observedValue<"))
        return Result::Error;

    // Generic roots publish their fields and methods even when no concrete instance exists.
    const size_t genericItem     = content.find("id=\"Compiler_doc_test_DocApi_GenericBox\"");
    const size_t genericFields   = content.find("<h3>Fields</h3>", genericItem);
    const size_t genericAlpha    = content.find(">alpha<", genericFields);
    const size_t genericInterp   = content.find(">interpolation<", genericFields);
    const size_t genericInWeight = content.find(">inWeight<", genericFields);
    const size_t genericValue    = content.find(">value</a>", genericFields);
    const size_t genericZeta     = content.find(">zeta<", genericFields);
    const size_t genericTableEnd = content.find("</table>", genericFields);
    const size_t genericDetail   = content.find("The detailed field description remains with its owner.", genericTableEnd);
    const size_t genericHeading  = content.find("id=\"Compiler_doc_test_DocApi_GenericBox_value_Semantics\"", genericTableEnd);
    const size_t genericMethod   = content.find("id=\"Compiler_doc_test_DocApi_GenericBox_get\"");
    if (genericItem == std::string::npos || genericFields == std::string::npos || genericAlpha == std::string::npos || genericInterp == std::string::npos || genericInWeight == std::string::npos || genericValue == std::string::npos || genericZeta == std::string::npos || genericTableEnd == std::string::npos || genericDetail == std::string::npos || genericHeading == std::string::npos || genericMethod == std::string::npos)
        return Result::Error;
    if (!(genericAlpha < genericInterp && genericInterp < genericInWeight && genericInWeight < genericValue && genericValue < genericZeta && genericZeta < genericTableEnd) || genericDetail < genericTableEnd)
        return Result::Error;
    if (content.contains(">hidden<") || content.contains("hiddenByAttribute") || content.contains("hiddenMethod") || content.contains("SECRET"))
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
    const size_t nextItem       = content.find("<div class=\"api-item ", orderedItem + 1);
    if (orderedItem == std::string::npos || orderedSummary == std::string::npos || orderedCode == std::string::npos || orderedSummary > orderedCode || (nextItem != std::string::npos && orderedCode > nextItem))
        return Result::Error;
    if (!content.contains(R"(<link rel="stylesheet" type="text/css" href="style.css">)"))
        return Result::Error;

    // A page owns everything it needs. It carries exactly one script, the one that searches the
    // index printed below it, and that script is inline: it asks for no second file.
    if (countOccurrences(content, "<script") != 1 || !content.contains("<script>") || content.contains("<?php"))
        return Result::Error;
    if (!content.contains(R"("s|Compiler_doc_test.DocApi.Counter|Compiler_doc_test_DocApi_Counter|A small public value used to verify methods and anonymous storage.")"))
        return Result::Error;
    if (!content.contains(R"("n|Compiler_doc_test.DocApi|namespace_Compiler_doc_test_DocApi|")"))
        return Result::Error;
    if (!content.contains(R"("v|Compiler_doc_test.DocApi.GenericBox.value|Compiler_doc_test_DocApi_GenericBox_value|Stored value.")") ||
        !content.contains(R"("k|Compiler_doc_test.DocApi.TestMode.Fast|Compiler_doc_test_DocApi_TestMode_Fast|Prefer lower latency.")") ||
        !content.contains(R"("f|Compiler_doc_test.DocApi.GenericBox.get|Compiler_doc_test_DocApi_GenericBox_get|Returns the stored value.")"))
        return Result::Error;

    // The kind of a symbol drives its accent, in the card and in the summary tables.
    if (!content.contains("<div class=\"api-item api-item-struct\">") || !content.contains("class=\"kind-chip kind-struct\""))
        return Result::Error;

    // The sidebar indexes every documented symbol so a reader never has to guess a spelling.
    if (!content.contains("<details class=\"toc-group\"") || !content.contains("<ul class=\"toc-symbols\">") || !content.contains("<span class=\"toc-label\">"))
        return Result::Error;

    const fs::path stylesheetPath = directory.root() / "style.css";
    SWC_RESULT(FileSystem::readTextFile(stylesheetPath, content, ioError));
    if (!content.contains(".site-header") || !content.contains(".code-block") || !content.contains(".search-panel"))
        return Result::Error;
    if (!content.contains("--swag-measure: 120ch;"))
        return Result::Error;
    if (!content.contains(".right {\n    min-width: 0;\n    /* Resolve the character measure once with the prose font.") || !content.contains("width: min(100%, var(--swag-measure));"))
        return Result::Error;
    if (!content.contains(".right p {\n    width: 100%;\n    max-width: 100%;\n    text-wrap: pretty;") || !content.contains(".container table,\n.code-block,\n.blockquote {\n    width: 100%;\n    max-width: 100%;"))
        return Result::Error;
    if (!content.contains("border-radius: 4px;") || !content.contains(".api-member-details") || !content.contains("clip-path: polygon(0 0, calc(100% - 18px)") || content.contains("scroll-behavior: smooth"))
        return Result::Error;
    if (!content.contains("--swag-rail-width: 328px;") || !content.contains("--swag-rail-width: 272px;") || !content.contains("overflow-x: hidden;") || !content.contains("text-overflow: ellipsis;"))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
