#pragma once
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

struct SemaNodeView;
class SymbolVariable;

namespace SemaCheck
{
    Result modifiers(Sema& sema, const AstNode& node, AstModifierFlags mods, AstModifierFlags allowed);
    Result isValue(Sema& sema, AstNodeRef nodeRef);
    Result isValueOrType(Sema& sema, SemaNodeView& view);
    Result isValueOrTypeInfo(Sema& sema, SemaNodeView& view);
    Result isConstant(Sema& sema, AstNodeRef nodeRef);
    Result isAssignable(Sema& sema, AstNodeRef nodeRef, const SemaNodeView& leftView);
    Result isValidSignature(Sema& sema, const std::vector<SymbolVariable*>& parameters, bool attribute);
}

SWC_END_NAMESPACE();
