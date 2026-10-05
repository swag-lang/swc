#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

void Cast::convertEnumToUnderlying(Sema& sema, SemaNodeView& view)
{
    const SymbolEnum* symEnum = SemaHelpers::enumSymbolFromTypeRef(sema, view.typeRef());
    if (!symEnum)
        return;

    if (view.cstRef().isValid())
    {
        sema.setConstant(view.nodeRef(), view.cst()->getEnumValue());
        view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        return;
    }

    createCast(sema, symEnum->underlyingTypeRef(), view.nodeRef());
    view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
}

SWC_END_NAMESPACE();
