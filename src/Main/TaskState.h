#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE();

class Symbol;
class SymbolFunction;

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
    SemaWaitMainThreadRunJit,
};

struct TaskState
{
    const SymbolFunction* runJitFunction   = nullptr;
    const SymbolFunction* codeGenFunction  = nullptr;
    const Symbol*         symbol           = nullptr;
    const Symbol*         waiterSymbol     = nullptr;
    AstNodeRef            nodeRef          = AstNodeRef::invalid();
    SourceCodeRef         codeRef          = SourceCodeRef::invalid();
    IdentifierRef         idRef            = IdentifierRef::invalid();
    TaskStateKind         kind             = TaskStateKind::None;
    bool                  jitEmissionError = false;

    static const char* kindName(TaskStateKind kind);
    const char*        kindName() const;
    bool               hasPauseReason() const;
    bool               canPause() const;
    void               setNone();
    void               setRunJit(const SymbolFunction* function, AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef);
    void               setSemaParsing(AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef);
    void               setCodeGenParsing(const SymbolFunction* function, AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef);
    void               setSemaWaitMainThreadRunJit(const SymbolFunction* function, AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef);
    void               reset();
};

SWC_END_NAMESPACE();
