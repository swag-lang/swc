#pragma once
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

class ConstantValue;
class TypeInfo;

struct SemaNodeView
{
    const AstNode*       node    = nullptr;
    const ConstantValue* cst     = nullptr;
    const TypeInfo*      type    = nullptr;
    Symbol*              sym     = nullptr;
    std::span<Symbol*>   symList = {};

    AstNodeRef  nodeRef = AstNodeRef::invalid();
    ConstantRef cstRef  = ConstantRef::invalid();
    TypeRef     typeRef = TypeRef::invalid();

    SemaNodeView(Sema& sema, AstNodeRef nodeRef)
    {
        nodeRef       = sema.semaInfo().getSubstituteRef(nodeRef);
        this->nodeRef = nodeRef;
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

    void setCstRef(Sema& sema, ConstantRef cstRef)
    {
        if (this->cstRef == cstRef)
            return;
        this->cstRef = cstRef;
        cst          = &sema.cstMgr().get(cstRef);
        typeRef      = cst->typeRef();
        type         = &sema.typeMgr().get(typeRef);
    }

    Result verifyUniqueSymbol(Sema& sema) const
    {
        if (symList.size() > 1)
            return SemaError::raiseAmbiguousSymbol(sema, nodeRef, symList);
        if (!sym)
            return SemaError::raiseInternal(sema, *node);
        return Result::Continue;
    }

    Result verifyNoneOrUniqueSymbol(Sema& sema) const
    {
        if (symList.size() > 1)
            return SemaError::raiseAmbiguousSymbol(sema, nodeRef, symList);
        return Result::Continue;
    }
};

SWC_END_NAMESPACE();
