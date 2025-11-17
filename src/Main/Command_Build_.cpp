#include "pch.h"
#include "Lexer/Lexer.h"
#include "Main/Command.h"
#include "Main/CompilerInstance.h"
#include "Main/FileManager.h"
#include "Main/Global.h"
#include "Parser/Ast.h"
#include "Parser/AstVisit.h"
#include "Parser/Parser.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

class SemaJob : public Job
{
    Ast*     ast_ = nullptr;
    AstVisit visit_;

    static AstVisit::Action preStmt(AstVisit& visit, AstNode& node)
    {
        return AstVisit::Action::Continue;
    }

public:
    SemaJob(const TaskContext& ctx, Ast* ast) :
        Job(ctx),
        ast_(ast)
    {
        func = [this](JobContext& jobCtx) {
            return exec(jobCtx);
        };
    }

    JobResult exec(JobContext& ctx)
    {
        visit_.run(*ast_, {.pre = &preStmt});
        return JobResult::Done;
    }
};

namespace
{
    void parseFile(JobContext& ctx, SourceFile* file)
    {
        if (file->loadContent(ctx) != Result::Success)
            return;

        auto& ast = file->ast();

        Lexer lexer;
        lexer.tokenize(ctx, ast.lexOut(), LexerFlagsE::Default);
        if (ast.lexOut().mustSkip())
            return;

        Parser parser;
        parser.parse(ctx, ast);
    }
}

namespace Command
{
    void build(CompilerInstance& compiler)
    {
        const TaskContext ctx(compiler.context());
        const auto&       global   = ctx.global();
        auto&             fileMgr  = compiler.context().fileMgr();
        auto&             jobMgr   = global.jobMgr();
        const auto        clientId = compiler.context().jobClientId();

        if (fileMgr.collectFiles(ctx) == Result::Error)
            return;

        for (const auto& f : fileMgr.files())
        {
            auto job  = std::make_shared<Job>(ctx);
            job->func = [f](JobContext& taskCtx) {
                parseFile(taskCtx, f);
                return JobResult::Done;
            };

            jobMgr.enqueue(job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);

        for (const auto& f : fileMgr.files())
        {
            auto job = std::make_shared<SemaJob>(ctx, &f->ast());
            jobMgr.enqueue(job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);
    }
}

SWC_END_NAMESPACE()
