#include "pch.h"
#include "Parser/ParserJob.h"
#include "Parser/Parser.h"
#include "Wmf/Verify.h"

SWC_BEGIN_NAMESPACE()

ParserJob::ParserJob(const TaskContext& ctx, SourceFile* file) :
    Job(ctx),
    file_(file)
{
    func = [this](JobContext& jobCtx) {
        return exec(jobCtx);
    };
}

JobResult ParserJob::exec(JobContext& ctx) const
{
    if (file_->loadContent(ctx) != Result::Success)
        return JobResult::Done;

    auto& ast = file_->ast();

    file_->unitTest().tokenize(ctx);

    Lexer lexer;
    lexer.tokenize(ctx, ast.lexOut(), LexerFlagsE::Default);
    if (ast.lexOut().mustSkip())
        return JobResult::Done;

    if (file_->unitTest().hasFlag(VerifyFlagsE::LexOnly))
        return JobResult::Done;

    Parser parser;
    parser.parse(ctx, ast);

    return JobResult::Done;
}

SWC_END_NAMESPACE()
