#include "pch.h"
#include "Sema/Type/SemaCast.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

void SemaCast::convertEnumToUnderlying(Sema& sema, SemaNodeView& nodeView)
{
    if (!nodeView.type->isEnum())
        return;

    if (nodeView.cstRef.isValid())
    {
        nodeView.setCstRef(sema, nodeView.cst->getEnumValue());
        return;
    }

    const SymbolEnum& symEnum = nodeView.type->enumSym();
    createImplicitCast(sema, symEnum.underlyingTypeRef(), nodeView.nodeRef);
}

void SemaCast::convertTypeToTypeValue(Sema& sema, SemaNodeView& nodeView)
{
    if (!nodeView.type->isType())
        return;

    TaskContext&      ctx    = sema.ctx();
    const ConstantRef cstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeTypeValue(ctx, nodeView.typeRef));
    nodeView.setCstRef(sema, cstRef);
    sema.semaInfo().setConstant(nodeView.nodeRef, cstRef);
}

namespace
{
    void typeToTypeValueForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
    {
        if (!self.type->isType())
            return;
        if (!other.type->isTypeValue())
            return;
        SemaCast::convertTypeToTypeValue(sema, self);
    }

    void enumForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
    {
        if (!self.type->isEnum())
            return;
        if (other.type->isEnum())
            return;
        SemaCast::convertEnumToUnderlying(sema, self);
    }
}

void SemaCast::convertForEquality(Sema& sema, SemaNodeView& leftNodeView, SemaNodeView& rightNodeView)
{
    if (!leftNodeView.type || !rightNodeView.type)
        return;

    typeToTypeValueForEquality(sema, leftNodeView, rightNodeView);
    typeToTypeValueForEquality(sema, rightNodeView, leftNodeView);
    enumForEquality(sema, leftNodeView, rightNodeView);
    enumForEquality(sema, rightNodeView, leftNodeView);
}

SWC_END_NAMESPACE()
