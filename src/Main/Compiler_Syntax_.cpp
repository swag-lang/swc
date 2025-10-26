#include "pch.h"

#include "Main/CommandLine.h"
#include "Main/Compiler.h"
#include "Main/FileManager.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Report/Diagnostic.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

Result Compiler::cmdSyntax()
{
    Context ctx(context_);

    if (context_.cmdLine_->folder.empty() && context_.cmdLine_->file.empty())
    {
        const auto diag = Diagnostic::error(DiagnosticId::CmdSyntaxNoInput);
        diag.report(ctx);
        return Result::Error;
    }

    std::vector<fs::path> paths;
    if (!context_.cmdLine_->folder.empty())
        FileSystem::collectSwagFilesRec(context_.cmdLine_->folder, paths);
    else
        paths.push_back(context_.cmdLine_->file);

    for (const auto& f : paths)
        context_.global().fileMgr().addFile(f);

    for (const auto& f : context_.global().fileMgr().files())
    {
        auto k   = std::make_shared<Job>(context_);
        k->func_ = [f](Context& ctx) {
            Parser parser;
            ctx.setSourceFile(f);
            parser.parse(ctx);
            return JobResult::Done;
        };

        context_.global().jobMgr().enqueue(k, JobPriority::Normal, context_.jobClientId());
    }

    context_.global().jobMgr().waitAll(context_.jobClientId());

    for (const auto& f : context_.global().fileMgr().files())
        f->verifier().verify(ctx);

    return Result::Success;
}

SWC_END_NAMESPACE();
