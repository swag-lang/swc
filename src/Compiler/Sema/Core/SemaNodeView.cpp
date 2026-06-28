#include "pch.h"
#include "Support/Report/Assert.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef nonNullTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return TypeRef::invalid();

        TypeRef nullableTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        if (nullableTypeRef.isInvalid())
            nullableTypeRef = typeRef;

        const TypeInfo& nullableType = sema.typeMgr().get(nullableTypeRef);
        if (!nullableType.isNullable())
            return TypeRef::invalid();

        TypeInfo resultType = nullableType;
        resultType.removeFlag(TypeInfoFlagsE::Nullable);
        return sema.typeMgr().addType(resultType);
    }
}

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

    const auto trySetTypeFromResolvedSymbol = [&] {
        if (!part.has(SemaNodeViewPartE::Type))
            return;

        const Symbol* sym = nullptr;
        if (hasSymbol_ && (!hasSymList_ || symList_.size() == 1))
            sym = sym_;

        if (!typeRef_.isValid())
        {
            if (!sym || !sym->typeRef().isValid())
                return;

            typeRef_ = sym->typeRef();
        }

        if (mode_ != SemaNodeViewResolveE::Stored && sema.frame().hasNonNullSymbol(sym))
        {
            const TypeRef narrowedTypeRef = nonNullTypeRef(sema, typeRef_);
            if (narrowedTypeRef.isValid())
                typeRef_ = narrowedTypeRef;
        }

        if (!typeRef_.isValid())
            return;

        type_ = &sema.typeMgr().get(typeRef_);
    };

    const bool needsResolvedSymbol = part.has(SemaNodeViewPartE::Symbol) || (part.has(SemaNodeViewPartE::Type) && mode != SemaNodeViewResolveE::Stored && sema.frame().hasNonNullSymbols());
    if (!needsResolvedSymbol)
        return;

    if (loadResolvedSymbols(sema, nodeRef_, mode))
    {
        trySetTypeFromResolvedSymbol();
        return;
    }

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

    trySetTypeFromResolvedSymbol();
}

void SemaNodeView::assignSymbolList(std::span<Symbol*> symbols)
{
    hasSymList_ = true;
    symList_    = symbols;
    hasSymbol_  = !symbols.empty();
    if (hasSymbol_)
        sym_ = symbols.front();
}

bool SemaNodeView::loadResolvedSymbols(const Sema& sema, AstNodeRef targetRef, SemaNodeViewResolveE resolveMode)
{
    // Read the symbol payload from a single snapshot. Splitting this into hasSymbol()/getSymbol()
    // (two separate atomic payload reads) races with a concurrent kind transition on shared
    // generic eval nodes and can reinterpret a non-symbol payload as a store offset.
    const NodePayload::ResolvedSymbols resolved = resolveMode == SemaNodeViewResolveE::Stored
                                                      ? sema.resolveSymbolsStored(targetRef)
                                                      : sema.resolveSymbols(targetRef);

    if (resolved.isSymbolList)
    {
        assignSymbolList({const_cast<Symbol**>(resolved.symbols.data()), resolved.symbols.size()});
        return true;
    }

    if (!resolved.symbols.empty())
    {
        hasSymbol_ = true;
        sym_       = const_cast<Symbol*>(resolved.symbols.front());
        return true;
    }

    return false;
}

void SemaNodeView::recompute(Sema& sema, SemaNodeViewPart part)
{
    SWC_ASSERT(queryNodeRef_.isValid());
    compute(sema, queryNodeRef_, part, mode_);
}

void SemaNodeView::getSymbols(SmallVector<Symbol*>& symbols) const
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Symbol));

    symbols.clear();

    if (hasSymList_)
    {
        symbols.reserve(symList_.size());
        for (auto* s : symList_)
            symbols.push_back(s);
    }
    else if (hasSymbol_)
    {
        symbols.push_back(sym_);
    }
}

Symbol* SemaNodeView::singleSymbol() const
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Symbol));

    if (hasSymList_)
        return symList_.size() == 1 ? symList_.front() : nullptr;

    return hasSymbol_ ? sym_ : nullptr;
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

std::span<Symbol* const> SemaNodeView::symList() const
{
    SWC_ASSERT(computedPart_.has(SemaNodeViewPartE::Symbol));
    return {symList_.data(), symList_.size()};
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
