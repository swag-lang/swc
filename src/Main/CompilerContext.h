#pragma once
#include "Lexer/SourceFile.h"

class CompilerContext
{
    SourceFile*             sourceFile_ = nullptr;
    const CompilerInstance* ci_         = nullptr;

public:
    explicit CompilerContext(const CompilerInstance* ci) :
        ci_(ci)
    {
    }

    const CompilerInstance& ci() const { return *ci_; }
    SourceFile*             sourceFile() const { return sourceFile_; }
    void                    setSourceFile(SourceFile* sourceFile) { sourceFile_ = sourceFile; }
};
