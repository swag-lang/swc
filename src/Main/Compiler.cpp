#include "pch.h"
#include "Main/Compiler.h"
#include "Core/Timer.h"
#include "FileManager.h"
#include "Lexer/SourceFile.h"
#include "Main/CompilerContext.h"
#include "Main/Global.h"
#include "Report/Stats.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

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
                    global_.fileMgr().addFile(entry.path());
                }
            }
        }
    };

    parseFolder("c:/perso/swag-lang/swag/bin");
    parseFolder("c:/perso/swag-lang/swc/tests");

    struct T : Job
    {
        SourceFile* f = nullptr;

        explicit T(const CommandLine& cmdLine, Global& global) :
            Job(cmdLine, global)
        {
        }

        JobResult process() override
        {
            f->loadContent(ctx_);
            if (f->codeView(0, static_cast<uint32_t>(f->content().size())).find("#global testerror") == Utf8::npos)
            {
                ctx_.setSourceFile(f);
                f->tokenize(ctx_);
                (void) f->verifier().verify(ctx_);
            }

            return JobResult::Done;
        }
    };

    for (const auto& f : global_.fileMgr().files())
    {
        auto k = std::make_shared<T>(cmdLine_, global_);
        k->f   = f;
        global_.jobMgr().enqueue(k, JobPriority::Normal);
    }

    global_.jobMgr().waitAll();
}

int Compiler::run() const
{
    {
        Timer time(&Stats::get().timeTotal);
        test();
    }

    if (cmdLine_.stats)
    {
        const CompilerContext ctx(&cmdLine_, &global_);
        Stats::get().print(ctx);
    }

    return 0;
}

SWC_END_NAMESPACE()
