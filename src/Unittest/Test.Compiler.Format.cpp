#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Compiler/SourceFile.h"
#include "Format/AstSourceWriter.h"
#include "Format/Formatter.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Memory/Heap.h"
#include "Support/Thread/JobManager.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct StatsRestoreGuard
    {
        size_t numErrors   = Stats::get().numErrors.load(std::memory_order_relaxed);
        size_t numWarnings = Stats::get().numWarnings.load(std::memory_order_relaxed);

        ~StatsRestoreGuard()
        {
            Stats::get().numErrors.store(numErrors, std::memory_order_relaxed);
            Stats::get().numWarnings.store(numWarnings, std::memory_order_relaxed);
        }
    };

    struct SilentDiagnosticGuard
    {
        TaskContext* ctx    = nullptr;
        bool         silent = false;

        explicit SilentDiagnosticGuard(TaskContext& context) :
            ctx(&context),
            silent(context.silentDiagnostic())
        {
            ctx->setSilentDiagnostic(true);
        }

        ~SilentDiagnosticGuard()
        {
            if (ctx)
                ctx->setSilentDiagnostic(silent);
        }
    };

    struct ScopedFileCleanup
    {
        fs::path path;

        ~ScopedFileCleanup()
        {
            std::error_code ec;
            fs::remove(path, ec);
        }
    };

    Result lexAndParseSource(TaskContext& ctx, SourceFile& sourceFile, const bool emitTrivia = true, const bool ignoreGlobalSkip = true)
    {
        const uint64_t errorsBefore = Stats::getNumErrors();

        SWC_RESULT(sourceFile.loadContent(ctx));

        LexerFlags lexerFlags = LexerFlagsE::Default;
        if (emitTrivia)
            lexerFlags.add(LexerFlagsE::EmitTrivia);
        if (ignoreGlobalSkip)
            lexerFlags.add(LexerFlagsE::IgnoreGlobalSkip);

        Lexer lexer;
        lexer.tokenize(ctx, sourceFile.ast().srcView(), lexerFlags);
        if (sourceFile.ast().srcView().mustSkip())
            return Result::Error;

        Parser parser;
        parser.parse(ctx, sourceFile.ast());
        if (Stats::getNumErrors() != errorsBefore)
            return Result::Error;

        return Result::Continue;
    }

    CommandLine makeFormatCommandLine(const std::string_view name)
    {
        CommandLine cmdLine;
        cmdLine.command = CommandKind::Format;
        cmdLine.name    = name;
        cmdLine.runtime = false;
        return cmdLine;
    }

    Format::Context makeFormatContext(TaskContext& ctx, SourceFile& sourceFile, const Format::Options& formatOptions)
    {
        return {
            .task    = &ctx,
            .file    = &sourceFile,
            .ast     = &sourceFile.ast(),
            .srcView = &sourceFile.ast().srcView(),
            .options = &formatOptions,
        };
    }

    Result parseFilesForFormat(TaskContext& ctx, CompilerInstance& compiler)
    {
        if (compiler.collectFiles(ctx) == Result::Error)
            return Result::Error;

        const uint64_t   errorsBefore = Stats::getNumErrors();
        ParserJobOptions parserOptions = {
            .emitTrivia       = true,
            .ignoreGlobalSkip = true,
        };

        JobManager&       jobMgr   = ctx.global().jobMgr();
        const JobClientId clientId = compiler.jobClientId();
        for (SourceFile* file : compiler.files())
        {
            auto* job = heapNew<ParserJob>(ctx, file, parserOptions);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);
        return Stats::getNumErrors() == errorsBefore ? Result::Continue : Result::Error;
    }
}

SWC_TEST_BEGIN(Compiler_FormatExactRoundTripPreservesTrivia)
{
    static constexpr std::string_view SOURCE =
        "\xEF\xBB\xBF// lead comment\r\n"
        "\r\n"
        "func Test() {\r\n"
        "\tlet x = 1\t// trailing comment   \r\n"
        "\r\n"
        "\t/* block\r\n"
        "\t   comment */\r\n"
        "\treturn\r\n"
        "}\r\n";

    CompilerInstance compiler(ctx.global(), makeFormatCommandLine("compiler_format_roundtrip"));
    TaskContext      compilerCtx(compiler);
    SourceFile&      sourceFile = Unittest::addTestSource(compilerCtx, "Compiler", "FormatExactRoundTripPreservesTrivia", SOURCE);

    SWC_RESULT(lexAndParseSource(compilerCtx, sourceFile));

    Format::Options formatOptions;
    Format::Context formatCtx = makeFormatContext(compilerCtx, sourceFile, formatOptions);

    SWC_RESULT(Format::AstSourceWriter::write(formatCtx));
    if (formatCtx.output.view() != SOURCE)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_FormatIgnoresGlobalSkipWhenRequested)
{
    static constexpr std::string_view SOURCE =
        "#global skip\r\n"
        "func Test() {\r\n"
        "\treturn\r\n"
        "}\r\n";

    CompilerInstance compiler(ctx.global(), makeFormatCommandLine("compiler_format_global_skip"));
    TaskContext      compilerCtx(compiler);
    SourceFile&      sourceFile = Unittest::addTestSource(compilerCtx, "Compiler", "FormatIgnoresGlobalSkipWhenRequested", SOURCE);

    SWC_RESULT(lexAndParseSource(compilerCtx, sourceFile));

    Format::Options formatOptions;
    Format::Context formatCtx = makeFormatContext(compilerCtx, sourceFile, formatOptions);

    SWC_RESULT(Format::AstSourceWriter::write(formatCtx));
    if (formatCtx.output.view() != SOURCE)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_FormatSkipsSkipFmtFiles)
{
    static constexpr std::string_view SOURCE =
        "#global skipfmt\r\n"
        "func Test() {\r\n"
        "\treturn\r\n"
        "}\r\n";

    CompilerInstance compiler(ctx.global(), makeFormatCommandLine("compiler_format_skipfmt"));
    TaskContext      compilerCtx(compiler);
    SourceFile&      sourceFile = Unittest::addTestSource(compilerCtx, "Compiler", "FormatSkipsSkipFmtFiles", SOURCE);

    SWC_RESULT(lexAndParseSource(compilerCtx, sourceFile));

    Format::Options formatOptions;
    Format::PreparedFile preparedFile;
    SWC_RESULT(Format::prepareFile(compilerCtx, sourceFile, formatOptions, preparedFile));

    if (!preparedFile.skipped)
        return Result::Error;
    if (preparedFile.changed)
        return Result::Error;
    if (preparedFile.text.view() != SOURCE)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_FormatRejectsIllFormedAst)
{
    static constexpr std::string_view SOURCE =
        "func Test() {\n"
        "    return\n"
        "}\n";

    CompilerInstance compiler(ctx.global(), makeFormatCommandLine("compiler_format_invalid_ast"));
    TaskContext      compilerCtx(compiler);
    SourceFile&      sourceFile = Unittest::addTestSource(compilerCtx, "Compiler", "FormatRejectsIllFormedAst", SOURCE);

    SWC_RESULT(lexAndParseSource(compilerCtx, sourceFile));

    StatsRestoreGuard    statsGuard;
    SilentDiagnosticGuard silentDiagnostics(compilerCtx);
    sourceFile.ast().setRoot(AstNodeRef::invalid());

    Format::Options formatOptions;
    Format::Context formatCtx = makeFormatContext(compilerCtx, sourceFile, formatOptions);

    if (Format::AstSourceWriter::write(formatCtx) != Result::Error)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_FormatCommandLeavesInvalidSourceUntouched)
{
    static constexpr std::string_view SOURCE =
        "func Test(\n"
        "{\n"
        "}\n";

    const fs::path     sourcePath = Unittest::makeTestSourcePath("Compiler", "FormatCommandLeavesInvalidSourceUntouched");
    ScopedFileCleanup  cleanup{sourcePath};
    StatsRestoreGuard  statsGuard;
    std::error_code    ec;

    fs::create_directories(sourcePath.parent_path(), ec);
    if (ec)
        return Result::Error;

    {
        std::ofstream stream(sourcePath, std::ios::binary | std::ios::trunc);
        if (!stream.is_open())
            return Result::Error;
        stream.write(SOURCE.data(), static_cast<std::streamsize>(SOURCE.size()));
        if (!stream)
            return Result::Error;
    }

    CommandLine cmdLine = makeFormatCommandLine("compiler_format_invalid_source");
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    if (parseFilesForFormat(compilerCtx, compiler) != Result::Error)
        return Result::Error;

    std::ifstream stream(sourcePath, std::ios::binary);
    if (!stream.is_open())
        return Result::Error;

    const std::string content((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
    if (content != SOURCE)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
