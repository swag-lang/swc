#pragma once
#include "Lexer/SourceFile.h"

class CompilerContext
{
    SourceFile* sourceFile_ = nullptr;

public:
    [[nodiscard]] SourceFile* sourceFile() const { return sourceFile_; }
    void                      setSourceFile(SourceFile* sourceFile) { sourceFile_ = sourceFile; }
};
