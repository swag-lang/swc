#include "pch.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

SemaNodeView::SemaNodeView(Sema& sema, AstNodeRef ref, SemaNodeViewPart part, SemaNodeViewResolveE mode)
{
    compute(sema, ref, part, mode);
}

void SemaNodeView::compute(Sema& sema, AstNodeRef ref, SemaNodeViewPart part, SemaNodeViewResolveE mode)
{
    // Reset everything first, as compute() can be called multiple times on the same view.
    node_         = nullptr;
    cst_          = nullptr;
    type_         = nullptr;
    sym_          = nullptr;
    symList_      = {};
    hasSymbol_    = false;
    hasSymList_   = false;
    queryNodeRef_ = ref;
    nodeRef_      = AstNodeRef::invalid();
    cstRef_       = ConstantRef::invalid();
    typeRef_      = TypeRef::invalid();
    computedPart_ = part;
    mode_         = mode;

    if (mode == SemaNodeViewResolveE::Stored)
        nodeRef_ = ref;
    else
        nodeRef_ = sema.getSubstituteRef(ref);
    if (!nodeRef_.isValid())
        return;

    if (part.has(SemaNodeViewPartE::Node))
        node_ = &sema.node(nodeRef_);

    if (part.has(SemaNodeViewPartE::Type))
    {
        if (mode == SemaNodeViewResolveE::Stored)
            typeRef_ = sema.typeRefOfStored(nodeRef_);
        else
            typeRef_ = sema.typeRefOf(nodeRef_);
        if (typeRef_.isValid())
            type_ = &sema.typeMgr().get(typeRef_);
    }

    if (part.has(SemaNodeViewPartE::Constant))
    {
        if (mode == SemaNodeViewResolveE::Stored)
            cstRef_ = sema.constantRefOfStored(nodeRef_);
        else
            cstRef_ = sema.constantRefOf(nodeRef_);
        if (cstRef_.isValid())
            cst_ = &sema.cstMgr().get(cstRef_);
    }

    if (!part.has(SemaNodeViewPartE::Symbol))
        return;

    const auto assignSymbolList = [this](std::span<Symbol*> symbols) {
        hasSymList_ = true;
        symList_    = symbols;
        hasSymbol_  = !symbols.empty();
        if (hasSymbol_)
            sym_ = symbols.front();
    };

    const auto loadResolvedSymbols = [this, &assignSymbolList, &sema](AstNodeRef targetRef, SemaNodeViewResolveE resolveMode) {
        if (resolveMode == SemaNodeViewResolveE::Stored)
        {
            if (sema.hasSymbolListStored(targetRef))
            {
                assignSymbolList(sema.getSymbolListStored(targetRef));
                return true;
            }

            if (sema.hasSymbolStored(targetRef))
            {
                hasSymbol_ = true;
                sym_       = &sema.symbolOfStored(targetRef);
                return true;
            }

            return false;
        }

        if (sema.hasSymbolList(targetRef))
        {
            assignSymbolList(sema.getSymbolList(targetRef));
            return true;
        }

        if (sema.hasSymbol(targetRef))
        {
            hasSymbol_ = true;
            sym_       = &sema.symbolOf(targetRef);
            return true;
        }

        return false;
    };

    if (loadResolvedSymbols(nodeRef_, mode))
        return;

    if (mode == SemaNodeViewResolveE::Stored)
        return;

    if (queryNodeRef_.isValid() && queryNodeRef_ != nodeRef_)
    {
        if (sema.hasSymbolListRaw(queryNodeRef_))
        {
            assignSymbolList(sema.getSymbolListRaw(queryNodeRef_));
        }
        else if (sema.hasSymbolRaw(queryNodeRef_))
        {
            hasSymbol_ = true;
            sym_       = &sema.symbolOfRaw(queryNodeRef_);
        }
    }
}

void SemaNodeView::recompute(Sema& sema, SemaNodeViewPart part)
{
    SWC_ASSERT(queryNodeRef_.isValid());
    compute(sema, queryNodeRef_, part, mode_);
}

void SemaNodeView::getSymbols(SmallVector<Symbol*>& symbols) const
{
    if (!symList_.empty())
    {
        for (auto* s : symList_)
            symbols.push_back(s);
    }
    else if (sym_)
    {
        symbols.push_back(sym_);
    }
}

const AstNode* SemaNodeView::node() const
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Node));
    return node_;
}

const AstNode*& SemaNodeView::node()
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Node));
    return node_;
}

const ConstantValue* SemaNodeView::cst() const
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Constant));
    return cst_;
}

const ConstantValue*& SemaNodeView::cst()
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Constant));
    return cst_;
}

const TypeInfo* SemaNodeView::type() const
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Type));
    return type_;
}

const TypeInfo*& SemaNodeView::type()
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Type));
    return type_;
}

Symbol* SemaNodeView::sym() const
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Symbol));
    return sym_;
}

Symbol*& SemaNodeView::sym()
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Symbol));
    return sym_;
}

std::span<Symbol*> SemaNodeView::symList() const
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Symbol));
    return symList_;
}

std::span<Symbol*>& SemaNodeView::symList()
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Symbol));
    return symList_;
}

AstNodeRef SemaNodeView::nodeRef() const
{
    return nodeRef_;
}

AstNodeRef& SemaNodeView::nodeRef()
{
    return nodeRef_;
}

ConstantRef SemaNodeView::cstRef() const
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Constant));
    return cstRef_;
}

ConstantRef& SemaNodeView::cstRef()
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Constant));
    return cstRef_;
}

TypeRef SemaNodeView::typeRef() const
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Type));
    return typeRef_;
}

TypeRef& SemaNodeView::typeRef()
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Type));
    return typeRef_;
}

bool SemaNodeView::hasType() const
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Type));
    return typeRef_.isValid();
}

bool SemaNodeView::hasConstant() const
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Constant));
    return cstRef_.isValid();
}

bool SemaNodeView::hasSymbol() const
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Symbol));
    return hasSymbol_;
}

bool SemaNodeView::hasSymbolList() const
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Symbol));
    return hasSymList_;
}

SWC_END_NAMESPACE();
