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
    TaskContext(const TaskContext& other);
    TaskContext& operator=(const TaskContext& other);
    TaskContext(TaskContext&&) noexcept            = default;
    TaskContext& operator=(TaskContext&&) noexcept = default;

    const Global&           global() const { return *(global_); }
    const CommandLine&      cmdLine() const { return *(cmdLine_); }
    bool                    hasCompiler() const { return compilerInstance_ != nullptr; }
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

    bool                      silentDiagnostic() const { return silentDiagnostic_; }
    void                      setSilentDiagnostic(bool silent) { silentDiagnostic_ = silent; }
    bool                      reportToStats() const { return reportToStats_; }
    void                      setReportToStats(bool reportToStats) { reportToStats_ = reportToStats; }
    bool                      muteOutput() const { return muteOutput_; }
    void                      setMuteOutput(bool mute) { muteOutput_ = mute; }
    void                      setHasError() { hasError_ = true; }
    void                      setHasWarning() { hasWarning_ = true; }
    bool                      hasError() const { return hasError_; }
    bool                      hasWarning() const { return hasWarning_; }
    std::shared_ptr<void>&    genericNodeRunCache() { return genericNodeRunCache_; }
    const std::shared_ptr<void>& genericNodeRunCache() const { return genericNodeRunCache_; }
    std::shared_ptr<void>&    genericInstanceNodeRunCache() { return genericInstanceNodeRunCache_; }
    const std::shared_ptr<void>& genericInstanceNodeRunCache() const { return genericInstanceNodeRunCache_; }
    std::shared_ptr<void>&    genericImplBlockRunCache() { return genericImplBlockRunCache_; }
    const std::shared_ptr<void>& genericImplBlockRunCache() const { return genericImplBlockRunCache_; }
    static const TaskContext* current() noexcept { return current_; }
    static const TaskContext* setCurrent(const TaskContext* ctx) noexcept;

private:
    friend class TaskScopedContext;

    const Global*                                 global_           = nullptr;
    const CommandLine*                            cmdLine_          = nullptr;
    CompilerInstance*                             compilerInstance_ = nullptr;
    bool                                          silentDiagnostic_ = false;
    bool                                          reportToStats_    = true;
    bool                                          muteOutput_       = false;
    bool                                          hasError_         = false;
    bool                                          hasWarning_       = false;
    TaskState                                     state_;
    std::shared_ptr<void>                         genericNodeRunCache_;
    std::shared_ptr<void>                         genericInstanceNodeRunCache_;
    std::shared_ptr<void>                         genericImplBlockRunCache_;
    inline static thread_local const TaskContext* current_ = nullptr;
};

class TaskScopedState final
{
public:
    TaskScopedState()                                  = delete;
    TaskScopedState(const TaskScopedState&)            = delete;
    TaskScopedState& operator=(const TaskScopedState&) = delete;

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

class TaskScopedContext final
{
public:
    TaskScopedContext()                                    = delete;
    TaskScopedContext(const TaskScopedContext&)            = delete;
    TaskScopedContext& operator=(const TaskScopedContext&) = delete;

    explicit TaskScopedContext(const TaskContext& ctx) :
        saved_(TaskContext::setCurrent(&ctx))
    {
    }

    ~TaskScopedContext()
    {
        TaskContext::setCurrent(saved_);
    }

    TaskScopedContext(TaskScopedContext&& other) noexcept :
        saved_(other.saved_)
    {
        other.saved_ = nullptr;
    }

    TaskScopedContext& operator=(TaskScopedContext&& other) noexcept
    {
        if (this == &other)
            return *this;

        TaskContext::setCurrent(saved_);
        saved_       = other.saved_;
        other.saved_ = nullptr;
        return *this;
    }

private:
    const TaskContext* saved_ = nullptr;
};

SWC_END_NAMESPACE();
