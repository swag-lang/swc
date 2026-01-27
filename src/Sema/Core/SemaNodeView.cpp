#include "pch.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

SemaNodeView::SemaNodeView(Sema& sema, AstNodeRef ref)
{
    compute(sema, ref);
}

void SemaNodeView::compute(Sema& sema, AstNodeRef ref)
{
    // Reset everything first, as compute() can be called multiple times on the same view.
    node    = nullptr;
    cst     = nullptr;
    type    = nullptr;
    sym     = nullptr;
    symList = {};
    nodeRef = AstNodeRef::invalid();
    cstRef  = ConstantRef::invalid();
    typeRef = TypeRef::invalid();

    nodeRef = sema.semaInfo().getSubstituteRef(ref);
    if (!nodeRef.isValid())
        return;

    node    = &sema.node(nodeRef);
    typeRef = sema.typeRefOf(nodeRef);
    if (typeRef.isValid())
        type = &sema.typeMgr().get(typeRef);
    if (sema.hasConstant(nodeRef))
        cstRef = sema.constantRefOf(nodeRef);
    if (cstRef.isValid())
        cst = &sema.cstMgr().get(cstRef);

    if (sema.hasSymbolList(nodeRef))
    {
        symList = sema.getSymbolList(nodeRef);
        sym     = symList.front();
    }
    else if (sema.hasSymbol(nodeRef))
    {
        sym = &sema.symbolOf(nodeRef);
    }
}

void SemaNodeView::setCstRef(Sema& sema, ConstantRef ref)
{
    if (cstRef == ref)
        return;

    cstRef  = ref;
    sym     = nullptr;
    symList = {};

    if (cstRef.isInvalid())
    {
        cst     = nullptr;
        type    = nullptr;
        typeRef = TypeRef::invalid();
        return;
    }

    cst     = &sema.cstMgr().get(cstRef);
    typeRef = cst->typeRef();
    type    = typeRef.isValid() ? &sema.typeMgr().get(typeRef) : nullptr;
}

void SemaNodeView::getSymbols(SmallVector<Symbol*>& symbols) const
{
    if (!symList.empty())
    {
        for (auto s : symList)
            symbols.push_back(s);
    }
    else if (sym)
    {
        symbols.push_back(sym);
    }
}

SWC_END_NAMESPACE();
