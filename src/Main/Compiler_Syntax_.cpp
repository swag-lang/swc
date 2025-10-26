#include "pch.h"

#include "FileManager.h"
#include "Global.h"
#include "Main/Compiler.h"
#include "Main/FileSystem.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

Result Compiler::cmdSyntax()
{
    std::vector<fs::path> paths;

    FileSystem::collectSwagFilesRec("C:/perso/swag-lang/swag/bin/testsuite/tests/compiler/src/legacy", paths);
    FileSystem::collectSwagFilesRec("C:/perso/swag-lang/swag/bin/std", paths);
    FileSystem::collectSwagFilesRec("C:/perso/swag-lang/swag/bin/examples", paths);
    FileSystem::collectSwagFilesRec("C:/perso/swag-lang/swag/bin/runtime", paths);
    FileSystem::collectSwagFilesRec("C:/perso/swag-lang/swag/bin/reference", paths);
    FileSystem::collectSwagFilesRec("c:/perso/swag-lang/swc/tests", paths);

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

    Context ctx(context_);
    for (const auto& f : context_.global().fileMgr().files())
        f->verifier().verify(ctx);

    return Result::Success;
}

SWC_END_NAMESPACE();
