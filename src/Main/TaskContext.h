#pragma once

SWC_BEGIN_NAMESPACE()

class CompilerInstance;
class ConstantManager;
class Global;
class SourceFile;
class TypeManager;
struct CommandLine;

enum class TaskStateKind : uint8_t
{
    None,
    SemaWaitingIdentifier,
};

struct TaskState
{
    TaskStateKind kind    = TaskStateKind::None;
    AstNodeRef    nodeRef = AstNodeRef::invalid();

    void reset()
    {
        kind    = TaskStateKind::None;
        nodeRef = AstNodeRef::invalid();
    }
};

class TaskContext
{
    const Global*      global_           = nullptr;
    const CommandLine* cmdLine_          = nullptr;
    CompilerInstance*  compilerInstance_ = nullptr;
    bool               silentDiagnostic_ = false;
    bool               hasError_         = false;
    bool               hasWarning_       = false;
    TaskState          state_;

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

    TaskState&             state() { return state_; }
    const TaskState&       state() const { return state_; }
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
