#pragma once
#include "Core/Result.h"
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;

namespace SemaCheck
{
    Result modifiers(Sema& sema, const AstNode& node, AstModifierFlags mods, AstModifierFlags allowed);
    Result isValueExpr(Sema& sema, AstNodeRef nodeRef);
    Result isConstant(Sema& sema, AstNodeRef nodeRef);
    Result checkSignature(Sema& sema, const std::vector<SymbolVariable*>& parameters, bool attribute);
}

SWC_END_NAMESPACE();
