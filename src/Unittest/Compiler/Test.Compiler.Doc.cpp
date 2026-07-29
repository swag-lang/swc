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
    char        arg4[] = "--ext";
    char        arg5[] = ".php";
    char        arg6[] = "--no-output-doc";
    char        arg7[] = "--doc-output-dir";
    char        arg8[] = "generated-doc";
    char*       argv[] = {arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8};

    CommandLineParser parser(const_cast<Global&>(ctx.global()), parserCmdLine);
    if (parser.parse(std::size(argv), argv) != Result::Continue)
        return Result::Error;

    if (parserCmdLine.command != CommandKind::Doc)
        return Result::Error;
    if (parserCmdLine.docCss != "site.css" || parserCmdLine.docExtension != ".php")
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

// Keep this compiler-only helper out of the API page.
#[Swag.NoDoc]
func hidden(value: s32)->s32
{
    return value
}
)";
    static constexpr std::string_view OUTPUT_NAME = "doc-test";
    static constexpr std::string_view OUTPUT_EXT  = ".html";
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
    genDoc.outputExtension          = runtimeString(OUTPUT_EXT);
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
    if (content.contains(">hidden<") || content.contains("func hidden"))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
