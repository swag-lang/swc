#include "pch.h"
#include "CompilerInstance.h"
#include "Core/Timer.h"
#include "Main/CompilerCommand.h"
#include "Main/FileManager.h"
#include "Main/Global.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    void parseFile(JobContext& ctx, SourceFile* file)
    {
#if SWC_HAS_STATS
        Timer time(&Stats::get().timeParser);
#endif

        if (file->loadContent(ctx) != Result::Success)
            return;

        file->unittest().tokenize(ctx);

        Lexer lexer;
        if (lexer.tokenize(ctx, file->lexOut(), LexerFlagsE::Default) != Result::Success)
            return;

        if (file->unittest().hasFlag(UnitTestFlagsE::LexOnly))
            return;

        Parser parser;
        parser.parse(ctx, file->parserOut(), file->lexOut());
    }
}

namespace CompilerCommand
{
    void syntax(const CompilerInstance& compiler)
    {
        TaskContext ctx(compiler.context());
        const auto& global  = ctx.global();
        auto&       fileMgr = global.fileMgr();

        if (fileMgr.collectFiles(ctx) == Result::Error)
            return;

        for (const auto& f : global.fileMgr().files())
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
            f->unittest().verifyUntouchedExpected(ctx, f->lexOut());
    }
}

SWC_END_NAMESPACE()
