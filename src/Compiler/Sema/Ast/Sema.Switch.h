#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;
class SymbolVariable;
class Sema;
struct AstSwitchStmt;
struct SemaNodeView;

// Case constant -> the node that introduced it. Shared by the runtime 'switch' and the
// compile-time '#static switch', which both check exhaustiveness the same way.
using SwitchSeenCases = std::unordered_map<ConstantRef, AstNodeRef>;

namespace SemaSwitch
{
    TypeRef enumTypeRef(Sema& sema, TypeRef typeRef);
    TypeRef caseCastTypeRef(Sema& sema, TypeRef switchTypeRef);
    Result  normalizeExprTypeInfoIfNeeded(Sema& sema, AstNodeRef exprRef, SemaNodeView& exprView);
    Result  validateExprType(Sema& sema, AstNodeRef exprRef, TypeRef exprTypeRef);
    Result  checkEnumExhaustive(Sema& sema, const SwitchSeenCases& seen, TypeRef exprTypeRef, AstNodeRef errorRef);
    // Whether some case always matches: '#complete' promises it for an enum, and a 'default'
    // arm provides it for anything. The payload only records the default of a switch that has
    // an expression, so the expressionless form - a case with neither a match expression nor a
    // 'where' guard - is recognized structurally.
    bool alwaysMatchesACase(Sema& sema, AstNodeRef switchRef, const AstSwitchStmt& switchStmt);
}

struct SwitchPayload
{
    SwitchSeenCases                         seen;
    std::unordered_map<TypeRef, AstNodeRef> seenDynamicTypes;

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
