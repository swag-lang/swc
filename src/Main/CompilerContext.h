#pragma once
#include "Lexer/SourceFile.h"

class CompilerContext
{
    Swc&        swc_;
    SourceFile* sourceFile_ = nullptr;

public:
    explicit CompilerContext(Swc& swc) :
        swc_(swc)
    {
    }

    Swc&        swc() const { return swc_; }
    SourceFile* sourceFile() const { return sourceFile_; }
    void        setSourceFile(SourceFile* sourceFile) { sourceFile_ = sourceFile; }
};
