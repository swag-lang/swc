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
    TaskStateKind        kind             = TaskStateKind::None;
    const SymbolFunction* runJitFunction  = nullptr;
    const SymbolFunction* codeGenFunction = nullptr;
    AstNodeRef    nodeRef      = AstNodeRef::invalid();
    SourceCodeRef codeRef      = SourceCodeRef::invalid();
    IdentifierRef idRef        = IdentifierRef::invalid();
    const Symbol* symbol       = nullptr;
    const Symbol* waiterSymbol = nullptr;

    void setNone()
    {
        kind             = TaskStateKind::None;
        runJitFunction   = nullptr;
        codeGenFunction  = nullptr;
        nodeRef          = AstNodeRef::invalid();
        codeRef          = SourceCodeRef::invalid();
        idRef            = IdentifierRef::invalid();
        symbol           = nullptr;
        waiterSymbol     = nullptr;
    }

    void setRunJit(const SymbolFunction* function, AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef)
    {
        kind             = TaskStateKind::RunJit;
        runJitFunction   = function;
        codeGenFunction  = nullptr;
        nodeRef          = currentNodeRef;
        codeRef          = currentCodeRef;
        idRef            = IdentifierRef::invalid();
        symbol           = nullptr;
        waiterSymbol     = nullptr;
    }

    void setSemaParsing(AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef)
    {
        kind             = TaskStateKind::SemaParsing;
        runJitFunction   = nullptr;
        codeGenFunction  = nullptr;
        nodeRef          = currentNodeRef;
        codeRef          = currentCodeRef;
        idRef            = IdentifierRef::invalid();
        symbol           = nullptr;
        waiterSymbol     = nullptr;
    }

    void setCodeGenParsing(const SymbolFunction* function, AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef)
    {
        kind             = TaskStateKind::CodeGenParsing;
        runJitFunction   = nullptr;
        codeGenFunction  = function;
        nodeRef          = currentNodeRef;
        codeRef          = currentCodeRef;
        idRef            = IdentifierRef::invalid();
        symbol           = nullptr;
        waiterSymbol     = nullptr;
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

SWC_END_NAMESPACE();
