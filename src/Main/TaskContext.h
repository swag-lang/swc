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
struct CommandLine;

enum class TaskStateKind : uint8_t
{
    None,
    SemaWaitIdentifier,
    SemaWaitCompilerDefined,
    SemaWaitImplRegistrations,
    SemaWaitSymDeclared,
    SemaWaitSymTyped,
    SemaWaitSymCompleted,
    SemaWaitTypeCompleted,
};

struct TaskState
{
    TaskStateKind kind         = TaskStateKind::None;
    AstNodeRef    nodeRef      = AstNodeRef::invalid();
    SourceCodeRef codeRef      = SourceCodeRef::invalid();
    IdentifierRef idRef        = IdentifierRef::invalid();
    const Symbol* symbol       = nullptr;
    const Symbol* waiterSymbol = nullptr;

    void reset()
    {
        kind         = TaskStateKind::None;
        nodeRef      = AstNodeRef::invalid();
        codeRef      = SourceCodeRef::invalid();
        idRef        = IdentifierRef::invalid();
        symbol       = nullptr;
        waiterSymbol = nullptr;
    }
};

class TaskContext
{
public:
    TaskContext() = delete;

    explicit TaskContext(const Global& global, const CommandLine& cmdLine);
    explicit TaskContext(CompilerInstance& compInst);

    const Global& global() const
    {
        SWC_ASSERT(global_);
        return *global_;
    }

    const CommandLine& cmdLine() const
    {
        SWC_ASSERT(cmdLine_);
        return *cmdLine_;
    }

    CompilerInstance& compiler()
    {
        SWC_ASSERT(compilerInstance_);
        return *compilerInstance_;
    }

    const CompilerInstance& compiler() const
    {
        SWC_ASSERT(compilerInstance_);
        return *compilerInstance_;
    }
    bool hasCompilerInstance() const { return compilerInstance_ != nullptr; }

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
