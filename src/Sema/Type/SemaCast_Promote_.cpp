#include "pch.h"
#include "Sema/Helpers/SemaNodeView.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/SemaCast.h"

SWC_BEGIN_NAMESPACE()

void SemaCast::promoteEnumToUnderlying(Sema& sema, SemaNodeView& nodeView)
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

void SemaCast::promoteTypeToTypeValue(Sema& sema, SemaNodeView& nodeView)
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
    void promoteTypeToTypeValueForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
    {
        if (!self.type->isType())
            return;        
        if (!other.type->isTypeValue())
            return;
        SemaCast::promoteTypeToTypeValue(sema, self);
    }

    void promoteEnumForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
    {
        if (!self.type->isEnum())
            return;
        if (other.type->isEnum())
            return;
        SemaCast::promoteEnumToUnderlying(sema, self);
    }
}

void SemaCast::promoteForEquality(Sema& sema, SemaNodeView& leftNodeView, SemaNodeView& rightNodeView)
{
    if (!leftNodeView.type || !rightNodeView.type)
        return;

    promoteTypeToTypeValueForEquality(sema, leftNodeView, rightNodeView);
    promoteTypeToTypeValueForEquality(sema, rightNodeView, leftNodeView);
    promoteEnumForEquality(sema, leftNodeView, rightNodeView);
    promoteEnumForEquality(sema, rightNodeView, leftNodeView);
}

SWC_END_NAMESPACE()
