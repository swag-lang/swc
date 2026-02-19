#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

void Cast::convertEnumToUnderlying(Sema& sema, SemaNodeView& view)
{
    if (!view.type()->isEnum())
        return;

    if (view.cstRef().isValid())
    {
        sema.setConstant(view.nodeRef(), view.cst()->getEnumValue());
        view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        return;
    }

    const SymbolEnum& symEnum = view.type()->payloadSymEnum();
    createCast(sema, symEnum.underlyingTypeRef(), view.nodeRef());
    view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
}

SWC_END_NAMESPACE();

