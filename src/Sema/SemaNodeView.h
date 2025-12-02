#pragma once
#include "Sema/Sema.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()
class ConstantValue;
class TypeInfo;

struct SemaNodeView
{
    const AstNode*       node    = nullptr;
    const ConstantValue* cst     = nullptr;
    ConstantRef          cstRef  = ConstantRef::invalid();
    TypeRef              typeRef = TypeRef::invalid();
    const TypeInfo*      type    = nullptr;

    SemaNodeView(Sema& sema, AstNodeRef nodeRef)
    {
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
    }
};

SWC_END_NAMESPACE()
