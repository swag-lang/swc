#include "pch.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Compiler/SourceFile.h"
#include "Compiler/Verify.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

Result parseLoadedSourceFile(TaskContext& ctx, SourceFile& file, const ParserJobOptions options)
{
    Ast& ast = file.ast();

    file.unitTest().tokenize(ctx);

    LexerFlags lexerFlags = LexerFlagsE::Default;
    if (options.emitTrivia)
        lexerFlags.add(LexerFlagsE::EmitTrivia);
    if (options.ignoreGlobalCompilerIfSkip)
        lexerFlags.add(LexerFlagsE::IgnoreGlobalCompilerIfSkip);
    if (options.allowReservedIdentifiers)
        lexerFlags.add(LexerFlagsE::AllowReservedIdentifiers);

    Lexer lexer;
    lexer.tokenize(ctx, ast.srcView(), lexerFlags);
    if (ast.srcView().mustSkip())
        return Result::Continue;

    if (!ast.srcView().runsParser())
        return Result::Continue;

    Parser parser;
    parser.parse(ctx, ast);

    return Result::Continue;
}

void parseSourceFiles(const TaskContext& ctx, const std::span<SourceFile* const> files, const ParserJobOptions options)
{
    TaskContext parserCtx(ctx);
    JobManager& jobMgr = ctx.global().jobMgr();
    jobMgr.parallelForIndexed(parserCtx, static_cast<uint32_t>(files.size()), JobKind::Parser, ctx.compiler().jobClientId(), [&](TaskContext& workerCtx, uint32_t index) {
        // A diagnostic belongs to one file. Reset the worker context before taking
        // another file, and leave the caller's context untouched in single-core mode.
        workerCtx = ctx;
        const TaskScopedContext scopedContext(workerCtx);
        SourceFile&             file = *files[index];
        if (file.loadContent(workerCtx) != Result::Continue)
            return;
        parseLoadedSourceFile(workerCtx, file, options);
    });
    // The indexed helper runs small/single-core batches inline. Keep the parser
    // stage's client barrier in those paths too, including an empty input set.
    jobMgr.waitAll(ctx.compiler().jobClientId());
}

SWC_END_NAMESPACE();
