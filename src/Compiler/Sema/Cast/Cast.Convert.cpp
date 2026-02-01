#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

void Cast::convertEnumToUnderlying(Sema& sema, SemaNodeView& nodeView)
{
    if (!nodeView.type->isEnum())
        return;

    if (nodeView.cstRef.isValid())
    {
        nodeView.setCstRef(sema, nodeView.cst->getEnumValue());
        return;
    }

    const SymbolEnum& symEnum = nodeView.type->payloadSymEnum();
    createImplicitCast(sema, symEnum.underlyingTypeRef(), nodeView.nodeRef);
    nodeView.compute(sema, nodeView.nodeRef);
}

void Cast::convertTypeToTypeValue(Sema& sema, SemaNodeView& nodeView)
{
    TaskContext&      ctx    = sema.ctx();
    const ConstantRef cstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeTypeValue(ctx, nodeView.typeRef));
    nodeView.setCstRef(sema, cstRef);
    sema.semaInfo().setConstant(nodeView.nodeRef, cstRef);
}

SWC_END_NAMESPACE();
