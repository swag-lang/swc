#pragma once
#include "Support/Core/SmallVector.h"
#include <unordered_map>

SWC_BEGIN_NAMESPACE();

class SymbolFunction;
class SymbolVariable;

struct SwitchPayload
{
    std::unordered_map<ConstantRef, AstNodeRef> seen;
    std::unordered_map<TypeRef, AstNodeRef>     seenDynamicTypes;

    TypeRef         exprTypeRef            = TypeRef::invalid();
    AstNodeRef      firstDefaultRef        = AstNodeRef::invalid();
    SymbolFunction* runtimePanicSymbol     = nullptr;
    bool            isComplete             = false;
    bool            hasRuntimeSwitchSafety = false;
};

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
