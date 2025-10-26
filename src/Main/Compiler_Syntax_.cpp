#include "pch.h"

#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/FileManager.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Report/Diagnostic.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

Result CompilerInstance::cmdSyntax()
{
    Context ctx(context_);

    // Syntax source files must be defined
    if (context_.cmdLine_->directories.empty() && context_.cmdLine_->files.empty())
    {
        const auto diag = Diagnostic::error(DiagnosticId::CmdSyntaxNoInput);
        diag.report(ctx);
        return Result::Error;
    }

    const auto global = context_.global();

    // Collect files
    std::vector<fs::path> paths;
    for (const auto& folder : context_.cmdLine_->directories)
        FileSystem::collectSwagFilesRec(folder, paths);
    for (const auto& file : context_.cmdLine_->files)
        paths.push_back(file);

    for (const auto& f : paths)
        global.fileMgr().addFile(f);

    for (const auto& f : global.fileMgr().files())
    {
        auto job   = std::make_shared<Job>(context_);
        job->func_ = [f](Context& fnCtx) {
            Parser parser;
            fnCtx.setSourceFile(f);
            parser.parse(fnCtx);
            return JobResult::Done;
        };

        global.jobMgr().enqueue(job, JobPriority::Normal, context_.jobClientId());
    }

    global.jobMgr().waitAll(context_.jobClientId());

    auto result = Result::Success;
    for (const auto& f : global.fileMgr().files())
    {
        if (f->unittest().verifyExpected(ctx) == Result::Error)
            result = Result::Error;
    }

    return result;
}

SWC_END_NAMESPACE();
