#pragma once
#include "Support/Core/PointerSet.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class Symbol;
class SymbolFunction;
class SymbolStruct;
class SymbolVariable;
class Sema;
class TypeInfo;
struct AstSwitchStmt;
struct SemaNodeView;

// Records the originating node for each case constant in runtime and static switches.
// Cases share a flat table, which allocates only when the first key is inserted.
template<typename K>
class SwitchCaseOrigins
{
public:
    // The node that already introduced the key, or null once 'nodeRef' is recorded for it.
    const AstNodeRef* tryAdd(K key, AstNodeRef nodeRef)
    {
        if (const AstNodeRef* previous = origins_.find(key.get()))
            return previous;

        origins_.emplace(key.get(), nodeRef);
        return nullptr;
    }

    bool contains(K key) const { return origins_.find(key.get()) != nullptr; }

private:
    FlatKeyMap<AstNodeRef> origins_;
};

using SwitchSeenCases = SwitchCaseOrigins<ConstantRef>;

namespace SemaSwitch
{
    bool            isDynamicType(Sema& sema, const TypeInfo& originalType);
    const TypeInfo* enumType(Sema& sema, const TypeInfo& originalType);
    TypeRef         caseCastTypeRef(Sema& sema, TypeRef switchTypeRef);
    Result          normalizeExprTypeInfoIfNeeded(Sema& sema, AstNodeRef exprRef, SemaNodeView& exprView);
    Result          validateExprType(Sema& sema, AstNodeRef exprRef, TypeRef exprTypeRef);
    Result          checkEnumExhaustive(Sema& sema, const SwitchSeenCases& seen, TypeRef exprTypeRef, AstNodeRef errorRef);

    // An enum's #complete or a default arm guarantees a match. Expressionless
    // switches do not record firstDefaultRef, so inspect their unguarded cases.
    bool alwaysMatchesACase(Sema& sema, AstNodeRef switchRef, const AstSwitchStmt& switchStmt);
}

struct SwitchPayload
{
    SwitchSeenCases            seen;
    SwitchCaseOrigins<TypeRef> seenDynamicTypes;

    TypeRef         exprTypeRef        = TypeRef::invalid();
    AstNodeRef      firstDefaultRef    = AstNodeRef::invalid();
    SymbolFunction* runtimePanicSymbol = nullptr;

    bool isComplete             = false;
    bool hasRuntimeSwitchSafety = false;

    bool escapeBranchPushed = false;

    // 'switch u' over a tagged union, or 'switch Swag.kindOf(u)': each case proves its values on
    // the union's path. A case falling through also proves the values of the cases before it.
    const SymbolStruct*         taggedUnion = nullptr;
    SmallVector4<const Symbol*> taggedPath;
    SmallVector<ConstantRef>    taggedCaseValues;
    SmallVector<ConstantRef>    taggedFallthroughValues;
};

struct DynamicStructSwitchCaseExpr
{
    AstNodeRef caseExprRef = AstNodeRef::invalid();
    AstNodeRef typeExprRef = AstNodeRef::invalid();
    AstNodeRef castRef     = AstNodeRef::invalid();
};

struct DynamicStructSwitchCasePayload
{
    SmallVector<DynamicStructSwitchCaseExpr, 2> expressions;

    SymbolVariable* bindingSymbol = nullptr;
};

struct DynamicStructSwitchAsCastPayload
{
};

SWC_END_NAMESPACE();
