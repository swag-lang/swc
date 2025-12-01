#pragma once
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE()

class Global;
struct CommandLine;
class SourceFile;

class TaskContext
{
    const Global*      global_           = nullptr;
    const CommandLine* cmdLine_          = nullptr;
    CompilerInstance*  compilerInstance_ = nullptr;
    bool               silentDiagnostic_ = false;
    bool               hasError_         = false;
    bool               hasWarning_       = false;

public:
    TaskContext() = delete;

    explicit TaskContext(const Global& global, const CommandLine& cmdLine) :
        global_(&global),
        cmdLine_(&cmdLine)
    {
    }

    explicit TaskContext(CompilerInstance& compInst) :
        compilerInstance_(&compInst)
    {
        global_  = &compInst.global();
        cmdLine_ = &compInst.cmdLine();
    }

    // clang-format off
    const Global&           global() const { SWC_ASSERT(global_); return *global_; }
    const CommandLine&      cmdLine() const { SWC_ASSERT(cmdLine_); return *cmdLine_; }
    CompilerInstance&       compiler() { SWC_ASSERT(compilerInstance_); return *compilerInstance_; }
    const CompilerInstance& compiler() const { SWC_ASSERT(compilerInstance_); return *compilerInstance_; }
    // clang-format on

    ConstantManager&       cstMgr() { return compiler().constMgr(); }
    const ConstantManager& cstMgr() const { return compiler().constMgr(); }
    TypeManager&           typeMgr() { return compiler().typeMgr(); }
    const TypeManager&     typeMgr() const { return compiler().typeMgr(); }

    bool silentDiagnostic() const { return silentDiagnostic_; }
    void setSilentDiagnostic(bool silent) { silentDiagnostic_ = silent; }
    void setHasError() { hasError_ = true; }
    void setHasWarning() { hasWarning_ = true; }
    bool hasError() const { return hasError_; }
    bool hasWarning() const { return hasWarning_; }
};

SWC_END_NAMESPACE()
