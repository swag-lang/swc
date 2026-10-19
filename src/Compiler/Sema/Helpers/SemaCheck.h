#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

struct SemaNodeView;
struct SourceCodeRef;
class SymbolFunction;
class SymbolVariable;

namespace SemaCheck
{
    Result modifiers(Sema& sema, const AstNode& node, AstModifierFlags mods, AstModifierFlags allowed);

    Result isValue(Sema& sema, AstNodeRef nodeRef);
    Result isValueOrType(Sema& sema, SemaNodeView& view);
    Result isValueOrTypeInfo(Sema& sema, SemaNodeView& view);

    Result prepareBoolExprValue(Sema& sema, SemaNodeView& view);
    Result castToBool(Sema& sema, SemaNodeView& view);
    Result conditionBinding(Sema& sema, AstNodeRef varDeclRef);
    Result typePattern(Sema& sema, AstNodeRef exprRef, bool binding = false);

    Result isConstant(Sema& sema, AstNodeRef nodeRef);

    bool   isReadOnlyParameterPath(Sema& sema, AstNodeRef nodeRef);
    bool   isImmutableBinding(Sema& sema, AstNodeRef nodeRef);
    bool   isConstAssignmentTarget(Sema& sema, AstNodeRef leftExprRef, const SemaNodeView& leftView);
    Result isAssignable(Sema& sema, AstNodeRef leftExprRef, const SemaNodeView& leftView, bool allowLetReferenceWriteThrough = false);

    Result isValidSignature(Sema& sema, const std::vector<SymbolVariable*>& parameters, bool attribute);

    Result noMoveRefType(Sema& sema, TypeRef typeRef, const SourceCodeRef& errorRef);
    Result noCopyOfNonCopyable(Sema& sema, AstNodeRef srcRef, TypeRef srcTypeRef, TypeRef destTypeRef, AstModifierFlags modifierFlags, bool destReferenceBinds, bool forceCopy = false);
    Result checkMoveSourceCanReset(Sema& sema, AstNodeRef srcRef, TypeRef typeRef, AstModifierFlags modifierFlags);

    void unreachableCode(Sema& sema, AstNodeRef blockRef, AstNodeRef childRef);

    // Block bodies returning a value must stop on every path; falling through
    // would emit no return. Expression bodies already supply the return value.
    Result missingReturn(Sema& sema, const SymbolFunction& sym, AstNodeRef bodyRef);

    // Report unused body declarations; intentionally unused parameters use ?.
    Result unusedVariables(Sema& sema, const SymbolFunction& sym);
}

SWC_END_NAMESPACE();
