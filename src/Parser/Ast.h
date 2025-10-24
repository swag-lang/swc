#pragma once
#include "Parser/AstNode.h"
#include "Parser/AstNodeExt.h"

SWC_BEGIN_NAMESPACE();

class Ast
{
    std::vector<AstNode> nodes_;
    AstNodeExt           extensions_;
};

SWC_END_NAMESPACE();
