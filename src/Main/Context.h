#pragma once
#include "Main/CompilerContext.h"

SWC_BEGIN_NAMESPACE()

class Global;
struct CommandLine;
class SourceFile;

class Context
{
    const CompilerContext* cmpContext_ = nullptr;
    SourceFile*            sourceFile_ = nullptr;

public:
    explicit Context(const CompilerContext& compContext) :
        cmpContext_(&compContext)
    {
    }

    const Global&      global() const { return cmpContext_->global(); }
    const CommandLine& cmdLine() const { return cmpContext_->cmdLine(); }
    SourceFile*        sourceFile() const { return sourceFile_; }
    void               setSourceFile(SourceFile* sourceFile) { sourceFile_ = sourceFile; }
};

SWC_END_NAMESPACE()
