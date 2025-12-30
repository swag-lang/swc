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
    SemaCast::createImplicitCast(sema, symEnum.underlyingTypeRef(), nodeView.nodeRef);
}

namespace
{
    void promoteTypeToTypeValue(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
    {
        if (self.type->isTypeValue())
            return;
        if (!other.type->isTypeValue())
            return;
        if (!self.type->isType())
            return;

        TaskContext&      ctx    = sema.ctx();
        const ConstantRef cstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeTypeValue(ctx, self.typeRef));
        self.setCstRef(sema, cstRef);
        sema.semaInfo().setConstant(self.nodeRef, cstRef);
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

    promoteTypeToTypeValue(sema, leftNodeView, rightNodeView);
    promoteTypeToTypeValue(sema, rightNodeView, leftNodeView);
    promoteEnumForEquality(sema, leftNodeView, rightNodeView);
    promoteEnumForEquality(sema, rightNodeView, leftNodeView);
}

SWC_END_NAMESPACE()
