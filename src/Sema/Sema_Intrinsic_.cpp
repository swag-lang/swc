#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/Sema.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstIntrinsicValue::semaPostNode(Sema& sema)
{
    // @temp
    setSemaType(sema.typeMgr().getTypeBool());
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
