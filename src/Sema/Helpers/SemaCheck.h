#pragma once
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE()

namespace SemaCheck
{
    AstStepResult modifiers(Sema& sema, const AstNode& node, AstModifierFlags mods, AstModifierFlags allowed);
    AstStepResult isValueExpr(Sema& sema, AstNodeRef nodeRef);
    AstStepResult isConstant(Sema& sema, AstNodeRef nodeRef);
}

SWC_END_NAMESPACE()
