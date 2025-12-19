#include "pch.h"
#include "Helpers/SemaFrame.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisitResult.h"
#include "Sema/Sema.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstEnumDecl::semaPreNode(Sema& sema)
{
    SemaFrame newFrame       = sema.frame();
    newFrame.currentEnumDecl = this;
    sema.pushFrame(newFrame);
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
