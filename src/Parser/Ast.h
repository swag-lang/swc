#pragma once
#include "Parser/AstExtStore.h"
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE();

class Ast
{
    std::vector<AstNode> nodes_;
    AstExtStore          extensions_;
};

SWC_END_NAMESPACE();
