#include "pch.h"

#include "Lexer/LangSpec.h"
#include "Lexer/SourceFile.h"
#include "Main/CommandLine.h"
#include "Main/CommandLineParser.h"
#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/DiagnosticIds.h"
#include "Report/Logger.h"
#include <filesystem>
#include <iostream>

static void parseFolder(CompilerContext& ctx, const fs::path& directory)
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
                f->loadContent(ctx);
                if (f->codeView(0, (uint32_t) f->content().size()).find("#global testerror") == Utf8::npos)
                {
                    ctx.setSourceFile(f);
                    f->tokenize(ctx);
                    (void) f->verifier().verify(ctx);
                }
            }
        }
    }
}

int main(int argc, char* argv[])
{
    const CompilerInstance ci;
    CompilerContext        ctx(&ci);
    CommandLineParser      parser;

    parser.setupCommandLine(ctx);
    if (!parser.parse(ctx, argc, argv, "build"))
        return 1;

    //parseFolder(ctx, "c:/perso/swag-lang");
    parseFolder(ctx, "c:/perso/swag-lang/swc");
    return 0;
}
