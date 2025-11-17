#include "pch.h"
#include "CompilerInstance.h"
#include "Main/Command.h"
#include "Main/FileManager.h"
#include "Main/Global.h"
#include "Parser/Ast.h"
#include "Parser/Parser.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"
#include "Wmf/UnitTest.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    void parseFile(JobContext& ctx, SourceFile* file)
    {
        if (file->loadContent(ctx) != Result::Success)
            return;

        file->unitTest().tokenize(ctx);

        Lexer lexer;
        lexer.tokenize(ctx, file->ast().lexOut(), LexerFlagsE::Default);
        if (file->ast().lexOut().mustSkip())
            return;

        if (file->unitTest().hasFlag(UnitTestFlagsE::LexOnly))
            return;

        Parser parser;
        parser.parse(ctx, file->ast());
    }
}

namespace Command
{
    void syntax(CompilerInstance& compiler)
    {
        TaskContext ctx(compiler.context());
        const auto& global  = ctx.global();
        auto&       fileMgr = compiler.context().fileMgr();

        if (fileMgr.collectFiles(ctx) == Result::Error)
            return;

        for (const auto& f : fileMgr.files())
        {
            auto job  = std::make_shared<Job>(ctx);
            job->func = [f](JobContext& taskCtx) {
                parseFile(taskCtx, f);
                return JobResult::Done;
            };

            global.jobMgr().enqueue(job, JobPriority::Normal, compiler.context().jobClientId());
        }

        global.jobMgr().waitAll(compiler.context().jobClientId());

        for (const auto& f : fileMgr.files())
        {
            if (f->ast().lexOut().mustSkip())
                continue;
            f->unitTest().verifyUntouchedExpected(ctx, f->ast().lexOut());
        }
    }
}

SWC_END_NAMESPACE()
