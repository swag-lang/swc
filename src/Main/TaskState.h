#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Support/Core/RefTypes.h"

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
    SemaWaitSymJitPrepared,
    SemaWaitSymJitPatched,
    SemaWaitSymJitCompleted,
    SemaWaitTypeCompleted,
    SemaWaitTypeInfoGeneration,
    SemaWaitMainThreadRunJit,
};

struct TaskState
{
    const SymbolFunction* runJitFunction           = nullptr;
    const SymbolFunction* codeGenFunction          = nullptr;
    const SymbolFunction* weakJitRelocationBlocker = nullptr;
    const Symbol*         symbol                   = nullptr;
    const Symbol*         waiterSymbol             = nullptr;
    AstNodeRef            nodeRef                  = AstNodeRef::invalid();
    SourceCodeRef         codeRef                  = SourceCodeRef::invalid();
    IdentifierRef         idRef                    = IdentifierRef::invalid();
    TaskStateKind         kind                     = TaskStateKind::None;
    bool                  jitEmissionError         = false;

    // Scope an unresolved `.member` was looked up in, when the identifier wait comes from
    // auto-scope resolution. It survives the pause so a stalled wait can still name the type
    // and list what it does offer, instead of degrading to a bare unknown-symbol report.
    TypeRef autoScopeTypeRef = TypeRef::invalid();

    static const char* kindName(TaskStateKind kind);
    bool               hasPauseReason() const;
    bool               canPause() const;
    void               setNone();
    void               setRunJit(const SymbolFunction* function, AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef);
    void               setSemaParsing(AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef);
    void               setCodeGenParsing(const SymbolFunction* function, AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef);
    void               setSemaWaitMainThreadRunJit(const SymbolFunction* function, AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef);
};

SWC_END_NAMESPACE();
