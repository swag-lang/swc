#pragma once

SWC_BEGIN_NAMESPACE()

struct CommandLine;
class Global;
class SourceFile;

class CompilerContext
{
    const CommandLine* cmdLine_    = nullptr;
    Global*            global_     = nullptr;
    SourceFile*        sourceFile_ = nullptr;

public:
    explicit CompilerContext(const CommandLine* cmdLine, Global* global) :
        cmdLine_(cmdLine),
        global_(global)
    {
    }

    Global*            global() const { return global_; }
    const CommandLine* cmdLine() const { return cmdLine_; }
    SourceFile*        sourceFile() const { return sourceFile_; }
    void               setSourceFile(SourceFile* sourceFile) { sourceFile_ = sourceFile; }
};

SWC_END_NAMESPACE()
