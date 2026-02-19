#include "pch.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

SemaNodeView::SemaNodeView(Sema& sema, AstNodeRef ref, SemaNodeViewPart part)
{
    compute(sema, ref, part);
}

void SemaNodeView::compute(Sema& sema, AstNodeRef ref, SemaNodeViewPart part)
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

    nodeRef = sema.getSubstituteRef(ref);
    if (!nodeRef.isValid())
        return;

    if (part.has(SemaNodeViewPartE::Node))
        node = &sema.node(nodeRef);

    if (part.has(SemaNodeViewPartE::Type))
    {
        typeRef = sema.typeRefOf(nodeRef);
        if (typeRef.isValid())
            type = &sema.typeMgr().get(typeRef);
    }

    if (part.has(SemaNodeViewPartE::Constant))
    {
        cstRef = sema.constantRefOf(nodeRef);
        if (cstRef.isValid())
            cst = &sema.cstMgr().get(cstRef);
    }

    if (!part.has(SemaNodeViewPartE::Symbol) && !part.has(SemaNodeViewPartE::SymbolList))
        return;

    if (sema.hasSymbolList(nodeRef))
    {
        const std::span<Symbol*> symbols = sema.getSymbolList(nodeRef);
        if (part.has(SemaNodeViewPartE::SymbolList))
            symList = symbols;
        if (part.has(SemaNodeViewPartE::Symbol) && !symbols.empty())
            sym = symbols.front();
    }
    else if (part.has(SemaNodeViewPartE::Symbol) && sema.hasSymbol(nodeRef))
    {
        sym = &sema.symbolOf(nodeRef);
    }
}

void SemaNodeView::recompute(Sema& sema, SemaNodeViewPart part)
{
    SWC_ASSERT(nodeRef.isValid());
    compute(sema, nodeRef, part);
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
