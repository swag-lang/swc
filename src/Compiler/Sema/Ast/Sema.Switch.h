#pragma once
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;

struct DynamicStructSwitchCaseExpr
{
    AstNodeRef caseExprRef = AstNodeRef::invalid();
    AstNodeRef typeExprRef = AstNodeRef::invalid();
};

struct DynamicStructSwitchCasePayload
{
    SmallVector<DynamicStructSwitchCaseExpr, 2> expressions;
    SymbolVariable*                             bindingSymbol = nullptr;
};

struct DynamicStructSwitchAsCastPayload
{
};

SWC_END_NAMESPACE();
