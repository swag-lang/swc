#include "pch.h"

#include "Lexer/SourceFile.h"
#include "Main/CommandLine.h"
#include "Main/CommandLineParser.h"
#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Thread/JobManager.h"

static void parseFolder(const fs::path& directory)
{
    if (!fs::exists(directory) || !fs::is_directory(directory))
    {
        std::cerr << "Invalid directory: " << directory << std::endl;
        return;
    }

    for (const auto& entry : fs::recursive_directory_iterator(directory))
    {
        if (entry.is_regular_file())
        {
            auto ext = entry.path().extension().string();
            if (ext == ".swg" || ext == ".swgs")
            {
                const auto f = new SourceFile(entry.path());

                struct t : Job
                {
                    SourceFile* f;
                    JobResult   process() override
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

                auto k = std::make_shared<t>();
                k->f   = f;
                CompilerInstance::get().jobMgr().enqueue(k, JobPriority::Normal);
                // printf("ADDED: %s\n", f->path().string().c_str());
            }
        }
    }
}

int main(int argc, char* argv[])
{
    auto& ci = CompilerInstance::get();
    ci.setup();

    CommandLineParser parser;
    parser.setupCommandLine();
    if (!parser.parse(argc, argv, "build"))
        return 1;

    ci.jobMgr().setNumThreads(ci.cmdLine().numCores);

    parseFolder("c:/perso/swag-lang/swag/bin");
    parseFolder("c:/perso/swag-lang/swc");

    ci.jobMgr().waitAll();
    return 0;
}
