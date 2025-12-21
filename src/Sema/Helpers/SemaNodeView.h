#pragma once
#include "Main/Command.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()
class ConstantValue;
class TypeInfo;

struct SemaNodeView
{
    const AstNode*       node = nullptr;
    const ConstantValue* cst  = nullptr;
    const TypeInfo*      type = nullptr;
    Symbol*              sym  = nullptr;

    AstNodeRef  nodeRef = AstNodeRef::invalid();
    ConstantRef cstRef  = ConstantRef::invalid();
    TypeRef     typeRef = TypeRef::invalid();

    SemaNodeView(Sema& sema, AstNodeRef nodeRef)
    {
        this->nodeRef = nodeRef;

        if (nodeRef.isValid())
        {
            node    = &sema.node(nodeRef);
            typeRef = sema.typeRefOf(nodeRef);
            type    = &sema.typeMgr().get(typeRef);
        }

        if (sema.hasConstant(nodeRef))
        {
            cstRef = sema.constantRefOf(nodeRef);
            cst    = &sema.constantOf(nodeRef);
        }
        else if (sema.hasSymbol(nodeRef))
        {
            sym = &sema.symbolOf(nodeRef);
        }
    }

    void setCstRef(Sema& sema, ConstantRef cstRef)
    {
        this->cstRef = cstRef;
        cst          = &sema.cstMgr().get(cstRef);
        typeRef      = cst->typeRef();
        type         = &sema.typeMgr().get(typeRef);
    }
};

struct SemaNodeViewList
{
    SmallVector<SemaNodeView, 4> view;

    SemaNodeViewList(Sema& sema, AstNodeRef lhs, AstNodeRef rhs)
    {
        view.emplace_back(sema, lhs);
        view.emplace_back(sema, rhs);
    }

    SemaNodeView& operator[](size_t index)
    {
        SWC_ASSERT(index < view.size());
        return view[index];
    }

    const SemaNodeView& operator[](size_t index) const
    {
        SWC_ASSERT(index < view.size());
        return view[index];
    }
};

SWC_END_NAMESPACE()
