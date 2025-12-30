#include "pch.h"
#include "Sema/Helpers/SemaNodeView.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/SemaCast.h"

SWC_BEGIN_NAMESPACE()

void SemaCast::promoteEnumToUnderlying(Sema& sema, SemaNodeView& nodeView)
{
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
    void promoteEnumForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
    {
        if (!self.type || !other.type)
            return;
        if (!self.type->isEnum())
            return;
        if (other.type->isEnum())
            return;
        SemaCast::promoteEnumToUnderlying(sema, self);
    }
}

void SemaCast::promoteForEquality(Sema& sema, SemaNodeView& leftNodeView, SemaNodeView& rightNodeView)
{
    promoteEnumForEquality(sema, leftNodeView, rightNodeView);
    promoteEnumForEquality(sema, rightNodeView, leftNodeView);
}

SWC_END_NAMESPACE()
