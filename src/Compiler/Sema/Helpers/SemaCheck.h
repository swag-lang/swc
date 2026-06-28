#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

struct SemaNodeView;
class SymbolVariable;

namespace SemaCheck
{
    Result modifiers(Sema& sema, const AstNode& node, AstModifierFlags mods, AstModifierFlags allowed);
    Result isValue(Sema& sema, AstNodeRef nodeRef);
    Result isValueOrType(Sema& sema, SemaNodeView& view);
    Result isValueOrTypeInfo(Sema& sema, SemaNodeView& view);
    Result prepareBoolExprValue(Sema& sema, SemaNodeView& view);
    Result castToBool(Sema& sema, SemaNodeView& view);
    Result isConstant(Sema& sema, AstNodeRef nodeRef);
    bool   isReadOnlyParameterPath(Sema& sema, AstNodeRef nodeRef);
    bool   isConstAssignmentTarget(Sema& sema, AstNodeRef leftExprRef, const SemaNodeView& leftView);
    Result isAssignable(Sema& sema, AstNodeRef errorNodeRef, AstNodeRef leftExprRef, const SemaNodeView& leftView, bool allowLetReferenceWriteThrough = false);
    Result isValidSignature(Sema& sema, const std::vector<SymbolVariable*>& parameters, bool attribute);
}

SWC_END_NAMESPACE();
