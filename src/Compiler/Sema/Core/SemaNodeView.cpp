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
    node_         = nullptr;
    cst_          = nullptr;
    type_         = nullptr;
    sym_          = nullptr;
    symList_      = {};
    nodeRef_      = AstNodeRef::invalid();
    cstRef_       = ConstantRef::invalid();
    typeRef_      = TypeRef::invalid();
    computedPart_ = part;

    nodeRef_ = sema.getSubstituteRef(ref);
    if (!nodeRef_.isValid())
        return;

    if (part.has(SemaNodeViewPartE::Node))
        node_ = &sema.node(nodeRef_);

    if (part.has(SemaNodeViewPartE::Type))
    {
        typeRef_ = sema.typeRefOf(nodeRef_);
        if (typeRef_.isValid())
            type_ = &sema.typeMgr().get(typeRef_);
    }

    if (part.has(SemaNodeViewPartE::Constant))
    {
        cstRef_ = sema.constantRefOf(nodeRef_);
        if (cstRef_.isValid())
            cst_ = &sema.cstMgr().get(cstRef_);
    }

    if (!part.has(SemaNodeViewPartE::Symbol) && !part.has(SemaNodeViewPartE::SymbolList))
        return;

    if (sema.hasSymbolList(nodeRef_))
    {
        const std::span<Symbol*> symbols = sema.getSymbolList(nodeRef_);
        if (part.has(SemaNodeViewPartE::SymbolList))
            symList_ = symbols;
        if (part.has(SemaNodeViewPartE::Symbol) && !symbols.empty())
            sym_ = symbols.front();
    }
    else if (part.has(SemaNodeViewPartE::Symbol) && sema.hasSymbol(nodeRef_))
    {
        sym_ = &sema.symbolOf(nodeRef_);
    }
}

void SemaNodeView::recompute(Sema& sema, SemaNodeViewPart part)
{
    SWC_ASSERT(nodeRef_.isValid());
    compute(sema, nodeRef_, part);
}

void SemaNodeView::getSymbols(SmallVector<Symbol*>& symbols) const
{
    if (!symList_.empty())
    {
        for (auto s : symList_)
            symbols.push_back(s);
    }
    else if (sym_)
    {
        symbols.push_back(sym_);
    }
}

void SemaNodeView::assertComputed(SemaNodeViewPartE part) const
{
    SWC_ASSERT(computedPart_.has(part));
}

const AstNode* SemaNodeView::node() const
{
    assertComputed(SemaNodeViewPartE::Node);
    return node_;
}

const AstNode*& SemaNodeView::node()
{
    assertComputed(SemaNodeViewPartE::Node);
    return node_;
}

const ConstantValue* SemaNodeView::cst() const
{
    assertComputed(SemaNodeViewPartE::Constant);
    return cst_;
}

const ConstantValue*& SemaNodeView::cst()
{
    assertComputed(SemaNodeViewPartE::Constant);
    return cst_;
}

const TypeInfo* SemaNodeView::type() const
{
    assertComputed(SemaNodeViewPartE::Type);
    return type_;
}

const TypeInfo*& SemaNodeView::type()
{
    assertComputed(SemaNodeViewPartE::Type);
    return type_;
}

Symbol* SemaNodeView::sym() const
{
    assertComputed(SemaNodeViewPartE::Symbol);
    return sym_;
}

Symbol*& SemaNodeView::sym()
{
    assertComputed(SemaNodeViewPartE::Symbol);
    return sym_;
}

std::span<Symbol*> SemaNodeView::symList() const
{
    assertComputed(SemaNodeViewPartE::SymbolList);
    return symList_;
}

std::span<Symbol*>& SemaNodeView::symList()
{
    assertComputed(SemaNodeViewPartE::SymbolList);
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
    assertComputed(SemaNodeViewPartE::Constant);
    return cstRef_;
}

ConstantRef& SemaNodeView::cstRef()
{
    assertComputed(SemaNodeViewPartE::Constant);
    return cstRef_;
}

TypeRef SemaNodeView::typeRef() const
{
    assertComputed(SemaNodeViewPartE::Type);
    return typeRef_;
}

TypeRef& SemaNodeView::typeRef()
{
    assertComputed(SemaNodeViewPartE::Type);
    return typeRef_;
}

SWC_END_NAMESPACE();
