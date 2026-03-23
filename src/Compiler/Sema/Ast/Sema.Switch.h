#pragma once
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;

struct DynamicStructSwitchBindingPayload
{
    AstNodeRef      caseExprRef = AstNodeRef::invalid();
    SymbolVariable* symbol      = nullptr;
};

SWC_END_NAMESPACE();
