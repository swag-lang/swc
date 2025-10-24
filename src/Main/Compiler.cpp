#include "pch.h"
#include "Main/Compiler.h"
#include "Core/Timer.h"
#include "FileManager.h"
#include "Lexer/SourceFile.h"
#include "Main/CommandLine.h"
#include "Main/EvalContext.h"
#include "Main/Global.h"
#include "Report/Stats.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

Compiler::Compiler(const CommandLine& cmdLine, const Global& global) :
    context_(cmdLine, global)
{
    context_.jobClientId_ = global.jobMgr().newClientId();
}

void Compiler::test() const
{
    auto parseFolder = [&](const fs::path& directory) {
        for (const auto& entry : fs::recursive_directory_iterator(directory))
        {
            if (entry.is_regular_file())
            {
                auto ext = entry.path().extension().string();
                if (ext == ".swg" || ext == ".swgs")
                {
                    context_.global().fileMgr().addFile(entry.path());
                }
            }
        }
    };

    parseFolder("C:/perso/swag-lang/swag/bin/testsuite/tests/compiler/src/legacy");
    parseFolder("C:/perso/swag-lang/swag/bin/std");
    parseFolder("C:/perso/swag-lang/swag/bin/examples");
    parseFolder("C:/perso/swag-lang/swag/bin/runtime");
    parseFolder("C:/perso/swag-lang/swag/bin/reference");

    parseFolder("c:/perso/swag-lang/swc/tests");

    struct T : Job
    {
        SourceFile* f = nullptr;

        explicit T(const CompilerContext& cmpCtx) :
            Job(cmpCtx)
        {
        }

        JobResult process() override
        {
            ctx_.setSourceFile(f);
            f->loadContent(ctx_);
            f->tokenize(ctx_);
            (void) f->verifier().verify(ctx_);
            return JobResult::Done;
        }
    };

    for (const auto& f : context_.global().fileMgr().files())
    {
        auto k = std::make_shared<T>(context_);
        k->f   = f;
        context_.global().jobMgr().enqueue(k, JobPriority::Normal, context_.jobClientId());
    }
}

int Compiler::run() const
{
    {
        Timer time(&Stats::get().timeTotal);
        test();
        context_.global().jobMgr().waitAll(context_.jobClientId());
    }

    if (context_.cmdLine().stats)
    {
        const EvalContext ctx(context_);
        Stats::get().print(ctx);
    }

    return 0;
}

SWC_END_NAMESPACE();
