#include "pch.h"

#include "Core/Timer.h"
#include "FileManager.h"
#include "Lexer/SourceFile.h"
#include "Main/CommandLine.h"
#include "Main/CommandLineParser.h"
#include "Main/CompilerContext.h"
#include "Main/Global.h"
#include "Report/Stats.h"
#include "Swc.h"
#include "Thread/JobManager.h"

void test()
{
    auto parseFolder = [](const fs::path& directory) {
        for (const auto& entry : fs::recursive_directory_iterator(directory))
        {
            if (entry.is_regular_file())
            {
                auto ext = entry.path().extension().string();
                if (ext == ".swg" || ext == ".swgs")
                {
                    Global::get().fileMgr().addFile(entry.path());
                }
            }
        }
    };

    parseFolder("c:/perso/swag-lang/swag/bin");
    parseFolder("c:/perso/swag-lang/swc/tests");

    struct t : Job
    {
        SourceFile* f;

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

    for (const auto& f : Global::get().fileMgr().files())
    {
        auto k = std::make_shared<t>();
        k->f   = f.get();
        Global::get().jobMgr().enqueue(k, JobPriority::Normal);
    }

    Global::get().jobMgr().waitAll();
}

int Swc::process(int argc, char* argv[])
{
    auto& ci = Global::get();
    ci.initialize();

    CommandLineParser parser;
    parser.setupCommandLine();
    if (!parser.parse(argc, argv, "build"))
        return -1;

    ci.jobMgr().setNumThreads(ci.cmdLine().numCores);

    test();
    return 0;
}

int Swc::go(int argc, char* argv[])
{
    Timer      time(&Stats::get().timeTotal);
    const auto result = process(argc, argv);
#if SWC_HAS_STATS
    Stats::get().print();
#endif
    return result;
}
