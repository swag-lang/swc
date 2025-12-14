#pragma once
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE()

namespace SemaCheck
{
    Result modifiers(Sema& sema, const AstNode& node, AstModifierFlags mods, AstModifierFlags allowed);
};

SWC_END_NAMESPACE()
