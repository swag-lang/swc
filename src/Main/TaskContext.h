#pragma once

SWC_BEGIN_NAMESPACE()

class CompilerInstance;
class ConstantManager;
class TypeManager;
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

    explicit TaskContext(const Global& global, const CommandLine& cmdLine);
    explicit TaskContext(CompilerInstance& compInst);

    // clang-format off
    const Global&           global() const { SWC_ASSERT(global_); return *global_; }
    const CommandLine&      cmdLine() const { SWC_ASSERT(cmdLine_); return *cmdLine_; }
    CompilerInstance&       compiler() { SWC_ASSERT(compilerInstance_); return *compilerInstance_; }
    const CompilerInstance& compiler() const { SWC_ASSERT(compilerInstance_); return *compilerInstance_; }
    // clang-format on

    ConstantManager&       cstMgr();
    const ConstantManager& cstMgr() const;
    TypeManager&           typeMgr();
    const TypeManager&     typeMgr() const;

    bool silentDiagnostic() const { return silentDiagnostic_; }
    void setSilentDiagnostic(bool silent) { silentDiagnostic_ = silent; }
    void setHasError() { hasError_ = true; }
    void setHasWarning() { hasWarning_ = true; }
    bool hasError() const { return hasError_; }
    bool hasWarning() const { return hasWarning_; }
};

SWC_END_NAMESPACE()
