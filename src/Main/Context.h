#pragma once
#include "Main/CommandLine.h"
#include "Main/CompilerContext.h"

SWC_BEGIN_NAMESPACE();

class CompilerContext;
class Global;
struct CommandLine;
class SourceFile;

class Context
{
    const CompilerContext* cmpContext_ = nullptr;
    SourceFile*            sourceFile_ = nullptr;
    CommandLine            cmdLine_;

public:
    explicit Context(const CompilerContext& compContext) :
        cmpContext_(&compContext),
        cmdLine_(compContext.cmdLine())
    {
    }

    const Global&      global() const { return cmpContext_->global(); }
    const CommandLine& cmdLine() const { return cmdLine_; }
    SourceFile*        sourceFile() const { return sourceFile_; }
    void               setSourceFile(SourceFile* sourceFile) { sourceFile_ = sourceFile; }
};

SWC_END_NAMESPACE();
