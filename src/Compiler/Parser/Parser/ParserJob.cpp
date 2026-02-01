#include "pch.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Wmf/SourceFile.h"
#include "Wmf/Verify.h"

SWC_BEGIN_NAMESPACE();

ParserJob::ParserJob(const TaskContext& ctx, SourceFile* file) :
    Job(ctx, JobKind::Parser),
    file_(file)
{
    func = [this] {
        return exec();
    };
}

JobResult ParserJob::exec()
{
    auto& jobCtx = ctx();
    if (file_->loadContent(jobCtx) != Result::Continue)
        return JobResult::Done;

    auto& ast = file_->ast();

    file_->unitTest().tokenize(jobCtx);

    Lexer lexer;
    lexer.tokenize(jobCtx, ast.srcView(), LexerFlagsE::Default);
    if (ast.srcView().mustSkip())
        return JobResult::Done;

    if (file_->unitTest().hasFlag(VerifyFlagsE::LexOnly))
        return JobResult::Done;

    Parser parser;
    parser.parse(jobCtx, ast);

    return JobResult::Done;
}

SWC_END_NAMESPACE();
