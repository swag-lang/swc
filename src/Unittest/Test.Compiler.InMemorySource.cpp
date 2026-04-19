#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(Compiler_InMemorySourceRunsSemaWithoutDiskIO)
{
    static constexpr std::string_view SOURCE     = R"(func A() {}
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "InMemorySourceRunsSemaWithoutDiskIO");

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Syntax;
    cmdLine.name    = "compiler_in_memory_source";

    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    TaskContext compilerCtx(compiler);

    SourceFile& sourceFile = compiler.addFile(sourcePath, FileFlagsE::CustomSrc);
    SWC_RESULT(sourceFile.loadContent(compilerCtx));

    Lexer lexer;
    lexer.tokenize(compilerCtx, sourceFile.ast().srcView(), LexerFlagsE::Default);
    if (sourceFile.ast().srcView().mustSkip())
        return Result::Error;

    Parser parser;
    parser.parse(compilerCtx, sourceFile.ast());

    const auto files = compiler.files();
    if (files.size() != 1)
        return Result::Error;

    const SourceFile* const file = files.front();
    if (!file)
        return Result::Error;
    if (!FileSystem::pathEquals(file->path(), sourcePath))
        return Result::Error;
    if (!file->ast().hasSourceView() || file->ast().root().isInvalid())
        return Result::Error;

    const SourceView* const srcView = compiler.findSourceViewByFileName(sourcePath.string());
    if (!srcView)
        return Result::Error;
    if (srcView->file() != file)
        return Result::Error;
    if (srcView->tokens().empty() || srcView->lines().empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_InMemorySourceTracksSkipFmtOnFile)
{
    static constexpr std::string_view SOURCE     = R"(#global skipfmt
func A() {}
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "InMemorySourceTracksSkipFmtOnFile");

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Syntax;
    cmdLine.name    = "compiler_in_memory_source_skipfmt";

    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    TaskContext compilerCtx(compiler);

    SourceFile& sourceFile = compiler.addFile(sourcePath, FileFlagsE::CustomSrc);
    SWC_RESULT(sourceFile.loadContent(compilerCtx));

    Lexer lexer;
    lexer.tokenize(compilerCtx, sourceFile.ast().srcView(), LexerFlagsE::Default);
    if (sourceFile.ast().srcView().mustSkip())
        return Result::Error;

    Parser parser;
    parser.parse(compilerCtx, sourceFile.ast());
    if (compilerCtx.hasError())
        return Result::Error;
    if (!sourceFile.mustSkipFormat())
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
