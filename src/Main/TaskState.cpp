#include "pch.h"
#include "Main/TaskState.h"

SWC_BEGIN_NAMESPACE();

const char* TaskState::kindName(const TaskStateKind kind)
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
        case TaskStateKind::SemaWaitMainThreadRunJit:
            return "Wait main-thread JIT";
        default:
            return "Unknown";
    }
}

const char* TaskState::kindName() const
{
    return kindName(kind);
}

bool TaskState::hasPauseReason() const
{
    switch (kind)
    {
        case TaskStateKind::SemaWaitIdentifier:
        case TaskStateKind::SemaWaitCompilerDefined:
        case TaskStateKind::SemaWaitImplRegistrations:
        case TaskStateKind::SemaWaitSymDeclared:
        case TaskStateKind::SemaWaitSymTyped:
        case TaskStateKind::SemaWaitSymSemaCompleted:
        case TaskStateKind::SemaWaitSymCodeGenPreSolved:
        case TaskStateKind::SemaWaitSymCodeGenCompleted:
        case TaskStateKind::SemaWaitTypeCompleted:
        case TaskStateKind::SemaWaitMainThreadRunJit:
            return true;

        default:
            return false;
    }
}

bool TaskState::canPause() const
{
    if (!hasPauseReason())
        return false;

    if (!codeRef.isValid())
        return false;

    switch (kind)
    {
        case TaskStateKind::SemaWaitIdentifier:
        case TaskStateKind::SemaWaitCompilerDefined:
        case TaskStateKind::SemaWaitImplRegistrations:
            return nodeRef.isValid() && idRef.isValid();

        case TaskStateKind::SemaWaitSymDeclared:
        case TaskStateKind::SemaWaitSymTyped:
        case TaskStateKind::SemaWaitSymSemaCompleted:
        case TaskStateKind::SemaWaitSymCodeGenPreSolved:
        case TaskStateKind::SemaWaitSymCodeGenCompleted:
            return nodeRef.isValid() && symbol != nullptr && waiterSymbol != nullptr;

        case TaskStateKind::SemaWaitTypeCompleted:
            return nodeRef.isValid() && waiterSymbol != nullptr;

        case TaskStateKind::SemaWaitMainThreadRunJit:
            return nodeRef.isValid() && runJitFunction != nullptr;

        default:
            return false;
    }
}

void TaskState::setNone()
{
    kind             = TaskStateKind::None;
    runJitFunction   = nullptr;
    codeGenFunction  = nullptr;
    nodeRef          = AstNodeRef::invalid();
    codeRef          = SourceCodeRef::invalid();
    idRef            = IdentifierRef::invalid();
    symbol           = nullptr;
    waiterSymbol     = nullptr;
    jitEmissionError = false;
}

void TaskState::setRunJit(const SymbolFunction* function, AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef)
{
    kind            = TaskStateKind::RunJit;
    runJitFunction  = function;
    codeGenFunction = nullptr;
    nodeRef         = currentNodeRef;
    codeRef         = currentCodeRef;
    idRef           = IdentifierRef::invalid();
    symbol          = nullptr;
    waiterSymbol    = nullptr;
}

void TaskState::setSemaParsing(AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef)
{
    kind            = TaskStateKind::SemaParsing;
    runJitFunction  = nullptr;
    codeGenFunction = nullptr;
    nodeRef         = currentNodeRef;
    codeRef         = currentCodeRef;
    idRef           = IdentifierRef::invalid();
    symbol          = nullptr;
    waiterSymbol    = nullptr;
}

void TaskState::setCodeGenParsing(const SymbolFunction* function, AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef)
{
    kind            = TaskStateKind::CodeGenParsing;
    runJitFunction  = nullptr;
    codeGenFunction = function;
    nodeRef         = currentNodeRef;
    codeRef         = currentCodeRef;
    idRef           = IdentifierRef::invalid();
    symbol          = nullptr;
    waiterSymbol    = nullptr;
}

void TaskState::setSemaWaitMainThreadRunJit(const SymbolFunction* function, AstNodeRef currentNodeRef, const SourceCodeRef& currentCodeRef)
{
    kind            = TaskStateKind::SemaWaitMainThreadRunJit;
    runJitFunction  = function;
    codeGenFunction = nullptr;
    nodeRef         = currentNodeRef;
    codeRef         = currentCodeRef;
    idRef           = IdentifierRef::invalid();
    symbol          = nullptr;
    waiterSymbol    = nullptr;
}

void TaskState::reset()
{
    setNone();
}

SWC_END_NAMESPACE();
