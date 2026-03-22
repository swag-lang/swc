#pragma once
#include "Main/TaskState.h"

SWC_BEGIN_NAMESPACE();

class IdentifierManager;
class CompilerInstance;
class ConstantManager;
class Global;
class SourceFile;
class TypeManager;
class TypeGen;
struct CommandLine;

class TaskContext
{
public:
    TaskContext() = delete;

    explicit TaskContext(const Global& global, const CommandLine& cmdLine);
    explicit TaskContext(CompilerInstance& compInst);

    const Global&           global() const { return *(global_); }
    const CommandLine&      cmdLine() const { return *(cmdLine_); }
    CompilerInstance&       compiler() { return *(compilerInstance_); }
    const CompilerInstance& compiler() const { return *(compilerInstance_); }

    TaskState&               state() { return state_; }
    const TaskState&         state() const { return state_; }
    ConstantManager&         cstMgr();
    const ConstantManager&   cstMgr() const;
    TypeManager&             typeMgr();
    const TypeManager&       typeMgr() const;
    TypeGen&                 typeGen();
    const TypeGen&           typeGen() const;
    IdentifierManager&       idMgr();
    const IdentifierManager& idMgr() const;

    bool silentDiagnostic() const { return silentDiagnostic_; }
    void setSilentDiagnostic(bool silent) { silentDiagnostic_ = silent; }
    void setHasError() { hasError_ = true; }
    void setHasWarning() { hasWarning_ = true; }
    bool hasError() const { return hasError_; }
    bool hasWarning() const { return hasWarning_; }

private:
    const Global*      global_           = nullptr;
    const CommandLine* cmdLine_          = nullptr;
    CompilerInstance*  compilerInstance_ = nullptr;
    bool               silentDiagnostic_ = false;
    bool               hasError_         = false;
    bool               hasWarning_       = false;
    TaskState          state_;
};

class TaskScopedState final
{
public:
    TaskScopedState() = delete;

    explicit TaskScopedState(TaskContext& ctx) :
        ctx_(&ctx),
        saved_(ctx.state())
    {
    }

    ~TaskScopedState()
    {
        if (ctx_)
            ctx_->state() = saved_;
    }

    TaskScopedState(const TaskScopedState&)            = delete;
    TaskScopedState& operator=(const TaskScopedState&) = delete;

    TaskScopedState(TaskScopedState&& other) noexcept :
        ctx_(other.ctx_),
        saved_(other.saved_)
    {
        other.ctx_ = nullptr;
    }

    TaskScopedState& operator=(TaskScopedState&& other) noexcept
    {
        if (this == &other)
            return *this;

        if (ctx_)
            ctx_->state() = saved_;

        ctx_       = other.ctx_;
        saved_     = other.saved_;
        other.ctx_ = nullptr;
        return *this;
    }

private:
    TaskContext* ctx_ = nullptr;
    TaskState    saved_;
};

SWC_END_NAMESPACE();
