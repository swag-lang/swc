#include "pch.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Compiler/SourceFile.h"
#include "Compiler/Verify.h"

SWC_BEGIN_NAMESPACE();

ParserJob::ParserJob(const TaskContext& ctx, SourceFile* file, const ParserJobOptions options) :
    Job(ctx, JobKind::Parser),
    file_(file),
    options_(options)
{
}

Result parseLoadedSourceFile(TaskContext& ctx, SourceFile& file, const ParserJobOptions options)
{
    Ast& ast = file.ast();

    file.unitTest().tokenize(ctx);

    LexerFlags lexerFlags = LexerFlagsE::Default;
    if (options.emitTrivia)
        lexerFlags.add(LexerFlagsE::EmitTrivia);
    if (options.ignoreGlobalSkip)
        lexerFlags.add(LexerFlagsE::IgnoreGlobalSkip);

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

JobResult ParserJob::exec()
{
    TaskContext& jobCtx = ctx();
    if (file_->loadContent(jobCtx) != Result::Continue)
        return JobResult::Done;

    return Job::toJobResult(jobCtx, parseLoadedSourceFile(jobCtx, *file_, options_));
}

SWC_END_NAMESPACE();
