#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;
class SymbolVariable;
class Sema;
struct SemaNodeView;

namespace SemaSwitch
{
    TypeRef enumTypeRef(Sema& sema, TypeRef typeRef);
    TypeRef caseCastTypeRef(Sema& sema, TypeRef switchTypeRef);
    Result  normalizeExprTypeInfoIfNeeded(Sema& sema, AstNodeRef exprRef, SemaNodeView& exprView);
    Result  validateExprType(Sema& sema, AstNodeRef exprRef, TypeRef exprTypeRef);
}

struct SwitchPayload
{
    std::unordered_map<ConstantRef, AstNodeRef> seen;
    std::unordered_map<TypeRef, AstNodeRef>     seenDynamicTypes;

    TypeRef         exprTypeRef            = TypeRef::invalid();
    AstNodeRef      firstDefaultRef        = AstNodeRef::invalid();
    SymbolFunction* runtimePanicSymbol     = nullptr;
    bool            isComplete             = false;
    bool            hasRuntimeSwitchSafety = false;
    bool            escapeBranchPushed     = false;
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
