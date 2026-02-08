#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE();

namespace ConstantHelpers
{
    ConstantRef makeSourceCodeLocation(Sema& sema, const AstNode& node);
}

SWC_END_NAMESPACE();
