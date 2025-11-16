#include "pch.h"
#include "Main/Command.h"
#include "Main/CompilerInstance.h"
#include "Main/FileManager.h"
#include "Main/Global.h"
#include "Parser/AstVisit.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    void parseFile(JobContext& ctx, SourceFile* file)
    {
        if (file->loadContent(ctx) != Result::Success)
            return;

        ctx.setSilentError(true);

        Lexer lexer;
        lexer.tokenize(ctx, file->lexOut(), LexerFlagsE::EmitTrivia);

        Parser parser;
        parser.parse(ctx, file->ast());

        AstVisit astVisit;
        astVisit.start(file->ast());
        astVisit.run();
    }
}

namespace Command
{
    void format(const CompilerInstance& compiler)
    {
        const TaskContext ctx(compiler.context());
        const auto&       global   = ctx.global();
        auto&             fileMgr  = global.fileMgr();
        const auto        clientId = compiler.context().jobClientId();

        if (fileMgr.collectFiles(ctx) == Result::Error)
            return;

        for (const auto& f : global.fileMgr().files())
        {
            auto job  = std::make_shared<Job>(ctx);
            job->func = [f](JobContext& taskCtx) {
                parseFile(taskCtx, f);
                return JobResult::Done;
            };

            global.jobMgr().enqueue(job, JobPriority::Normal, clientId);
        }

        global.jobMgr().waitAll(clientId);
    }
}

SWC_END_NAMESPACE()
