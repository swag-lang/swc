#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstIntrinsicValue::semaPostNode(Sema& sema)
{
    sema.semaInfo().setType(sema.curNodeRef(), sema.typeMgr().getTypeBool());
    SemaInfo::addSemaFlags(*this, NodeSemaFlags::ValueExpr);

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
