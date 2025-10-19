#include "pch.h"

#include "Lexer/SourceFile.h"
#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/Logger.h"
#include "Report/Reporter.h"
#include "Lexer/LangSpec.h"
#include <filesystem>
#include <iostream>

void parseFolder(CompilerInstance& ci, CompilerContext &ctx, const fs::path& directory)
{
    if (!fs::exists(directory) || !fs::is_directory(directory)) {
        std::cerr << "Invalid directory: " << directory << std::endl;
        return;
    }

    for (const auto& entry : fs::recursive_directory_iterator(directory)) {
        if (entry.is_regular_file()) {
            auto ext = entry.path().extension().string();
            if (ext == ".swg" || ext == ".swgs") {
                auto f = new SourceFile(entry.path());
                f->loadContent(ci, ctx);
                ctx.setSourceFile(f);
                f->tokenize(ci, ctx);
            }
        }
    }
}

int main(int argc, char* argv[])
{
    CompilerInstance ci;
    CompilerContext ctx;
    parseFolder(ci, ctx, "c:/perso/swag-lang");
    return 0;
}
