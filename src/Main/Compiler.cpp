#include "pch.h"
#include "Main/Compiler.h"
#include "Core/Timer.h"
#include "FileManager.h"
#include "Lexer/SourceFile.h"
#include "Main/CommandLine.h"
#include "Main/Context.h"
#include "Main/Global.h"
#include "Parser/Parser.h"
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
                    if (!context_.cmdLine().fileFilter.empty() && entry.path().filename().string().find(context_.cmdLine().fileFilter) == Utf8::npos)
                        continue;
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
    {
        f->verifier().verify(ctx);
    }
}

int Compiler::run() const
{
    {
        Timer time(&Stats::get().timeTotal);
        test();
    }

    if (context_.cmdLine().stats)
    {
        const Context ctx(context_);
        Stats::get().print(ctx);
    }

    return 0;
}

SWC_END_NAMESPACE();
