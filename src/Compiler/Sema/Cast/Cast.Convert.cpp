#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

void Cast::convertEnumToUnderlying(Sema& sema, SemaNodeView& view)
{
    TypeRef enumTypeRef = view.typeRef();
    if (!enumTypeRef.isValid())
        return;

    if (!sema.typeMgr().get(enumTypeRef).isEnum())
    {
        enumTypeRef = sema.typeMgr().get(enumTypeRef).unwrap(sema.ctx(), enumTypeRef, TypeExpandE::Alias);
        if (!enumTypeRef.isValid() || !sema.typeMgr().get(enumTypeRef).isEnum())
            return;
    }

    const TypeInfo& enumType = sema.typeMgr().get(enumTypeRef);
    if (!enumType.isEnum())
        return;

    if (view.cstRef().isValid())
    {
        sema.setConstant(view.nodeRef(), view.cst()->getEnumValue());
        view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        return;
    }

    const SymbolEnum& symEnum = enumType.payloadSymEnum();
    createCast(sema, symEnum.underlyingTypeRef(), view.nodeRef());
    view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
}

SWC_END_NAMESPACE();
