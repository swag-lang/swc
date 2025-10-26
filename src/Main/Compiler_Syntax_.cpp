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

    if (context_.cmdLine_->directories.empty() && context_.cmdLine_->files.empty())
    {
        const auto diag = Diagnostic::error(DiagnosticId::CmdSyntaxNoInput);
        diag.report(ctx);
        return Result::Error;
    }

    const auto global = context_.global();

    std::vector<fs::path> paths;
    for (const auto& folder : context_.cmdLine_->directories)
        FileSystem::collectSwagFilesRec(folder, paths);
    for (const auto& file : context_.cmdLine_->files)
        paths.push_back(file);

    for (const auto& f : paths)
        global.fileMgr().addFile(f);

    for (const auto& f : global.fileMgr().files())
    {
        auto k   = std::make_shared<Job>(context_);
        k->func_ = [f](Context& fnCtx) {
            Parser parser;
            fnCtx.setSourceFile(f);
            parser.parse(fnCtx);
            return JobResult::Done;
        };

        global.jobMgr().enqueue(k, JobPriority::Normal, context_.jobClientId());
    }

    global.jobMgr().waitAll(context_.jobClientId());

    for (const auto& f : global.fileMgr().files())
        f->verifier().verify(ctx);

    return Result::Success;
}

SWC_END_NAMESPACE();
