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

JobResult ParserJob::exec()
{
    TaskContext& jobCtx = ctx();
    if (file_->loadContent(jobCtx) != Result::Continue)
        return JobResult::Done;

    Ast& ast = file_->ast();

    file_->unitTest().tokenize(jobCtx);

    LexerFlags lexerFlags = LexerFlagsE::Default;
    if (options_.emitTrivia)
        lexerFlags.add(LexerFlagsE::EmitTrivia);
    if (options_.ignoreGlobalSkip)
        lexerFlags.add(LexerFlagsE::IgnoreGlobalSkip);

    Lexer lexer;
    lexer.tokenize(jobCtx, ast.srcView(), lexerFlags);
    if (ast.srcView().mustSkip())
        return JobResult::Done;

    if (!ast.srcView().runsParser())
        return JobResult::Done;

    Parser parser;
    parser.parse(jobCtx, ast);

    return JobResult::Done;
}

SWC_END_NAMESPACE();
