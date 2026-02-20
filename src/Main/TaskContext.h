#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE();

class IdentifierManager;
class CompilerInstance;
class ConstantManager;
class Global;
class SourceFile;
class TypeManager;
class TypeGen;
class Symbol;
class SymbolFunction;
struct CommandLine;

enum class TaskStateKind : uint8_t
{
    None,
    RunJit,
    SemaParsing,
    CodeGenParsing,
    SemaWaitIdentifier,
    SemaWaitCompilerDefined,
    SemaWaitImplRegistrations,
    SemaWaitSymDeclared,
    SemaWaitSymTyped,
    SemaWaitSymSemaCompleted,
    SemaWaitSymCodeGenPreSolved,
    SemaWaitSymCodeGenCompleted,
    SemaWaitTypeCompleted,
};

struct TaskState
{
    const SymbolFunction* runJitFunction       = nullptr;
    const SymbolFunction* codeGenFunction      = nullptr;
    const Symbol*         symbol               = nullptr;
    const Symbol*         waiterSymbol         = nullptr;
    IdentifierRef         runJitFunctionIdRef  = IdentifierRef::invalid();
    IdentifierRef         codeGenFunctionIdRef = IdentifierRef::invalid();
    AstNodeRef            nodeRef              = AstNodeRef::invalid();
    SourceCodeRef         codeRef              = SourceCodeRef::invalid();
    IdentifierRef         idRef                = IdentifierRef::invalid();
    TaskStateKind         kind                 = TaskStateKind::None;

    static const char* kindName(TaskStateKind kind)
    {
        switch (kind)
        {
            case TaskStateKind::None:
                return "None";
            case TaskStateKind::RunJit:
                return "Run JIT";
            case TaskStateKind::SemaParsing:
                return "Semantic parsing";
            case TaskStateKind::CodeGenParsing:
                return "Codegen parsing";
            case TaskStateKind::SemaWaitIdentifier:
                return "Wait identifier";
            case TaskStateKind::SemaWaitCompilerDefined:
                return "Wait compiler-defined";
            case TaskStateKind::SemaWaitImplRegistrations:
                return "Wait impl registrations";
            case TaskStateKind::SemaWaitSymDeclared:
                return "Wait symbol declared";
            case TaskStateKind::SemaWaitSymTyped:
                return "Wait symbol typed";
            case TaskStateKind::SemaWaitSymSemaCompleted:
                return "Wait symbol sema completed";
            case TaskStateKind::SemaWaitSymCodeGenPreSolved:
                return "Wait symbol codegen pre-solved";
            case TaskStateKind::SemaWaitSymCodeGenCompleted:
                return "Wait symbol codegen completed";
            case TaskStateKind::SemaWaitTypeCompleted:
                return "Wait type completed";
            default:
                return "Unknown";
        }
    }

    const char* kindName() const
    {
        return kindName(kind);
    }

    void setNone()
    {
        kind                 = TaskStateKind::None;
        runJitFunction       = nullptr;
        runJitFunctionIdRef  = IdentifierRef::invalid();
        codeGenFunction      = nullptr;
        codeGenFunctionIdRef = IdentifierRef::invalid();
        nodeRef              = AstNodeRef::invalid();
        codeRef              = SourceCodeRef::invalid();
        idRef                = IdentifierRef::invalid();
        symbol               = nullptr;
        waiterSymbol         = nullptr;
    }

    void setRunJit(const SymbolFunction* function, IdentifierRef functionIdRef, AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef)
    {
        kind                 = TaskStateKind::RunJit;
        runJitFunction       = function;
        runJitFunctionIdRef  = functionIdRef;
        codeGenFunction      = nullptr;
        codeGenFunctionIdRef = IdentifierRef::invalid();
        nodeRef              = currentNodeRef;
        codeRef              = currentCodeRef;
        idRef                = IdentifierRef::invalid();
        symbol               = nullptr;
        waiterSymbol         = nullptr;
    }

    void setSemaParsing(AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef)
    {
        kind                 = TaskStateKind::SemaParsing;
        runJitFunction       = nullptr;
        runJitFunctionIdRef  = IdentifierRef::invalid();
        codeGenFunction      = nullptr;
        codeGenFunctionIdRef = IdentifierRef::invalid();
        nodeRef              = currentNodeRef;
        codeRef              = currentCodeRef;
        idRef                = IdentifierRef::invalid();
        symbol               = nullptr;
        waiterSymbol         = nullptr;
    }

    void setCodeGenParsing(const SymbolFunction* function, IdentifierRef functionIdRef, AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef)
    {
        kind                 = TaskStateKind::CodeGenParsing;
        runJitFunction       = nullptr;
        runJitFunctionIdRef  = IdentifierRef::invalid();
        codeGenFunction      = function;
        codeGenFunctionIdRef = functionIdRef;
        nodeRef              = currentNodeRef;
        codeRef              = currentCodeRef;
        idRef                = IdentifierRef::invalid();
        symbol               = nullptr;
        waiterSymbol         = nullptr;
    }

    void reset()
    {
        setNone();
    }
};

class TaskContext
{
public:
    TaskContext() = delete;

    explicit TaskContext(const Global& global, const CommandLine& cmdLine);
    explicit TaskContext(CompilerInstance& compInst);

    const Global&           global() const { return *SWC_CHECK_NOT_NULL(global_); }
    const CommandLine&      cmdLine() const { return *SWC_CHECK_NOT_NULL(cmdLine_); }
    CompilerInstance&       compiler() { return *SWC_CHECK_NOT_NULL(compilerInstance_); }
    const CompilerInstance& compiler() const { return *SWC_CHECK_NOT_NULL(compilerInstance_); }

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
