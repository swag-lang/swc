#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

void Cast::convertEnumToUnderlying(Sema& sema, SemaNodeView& nodeView)
{
    if (!nodeView.type()->isEnum())
        return;

    if (nodeView.cstRef().isValid())
    {
        sema.setConstant(nodeView.nodeRef(), nodeView.cst()->getEnumValue());
        nodeView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        return;
    }

    const SymbolEnum& symEnum = nodeView.type()->payloadSymEnum();
    createCast(sema, symEnum.underlyingTypeRef(), nodeView.nodeRef());
    nodeView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
}

SWC_END_NAMESPACE();

