#include "pch.h"

#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/Symbols.h"
#include "SemaNodeView.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstVarDecl::semaPostNode(Sema& sema) const
{
    SemaNodeView type(sema, nodeTypeRef);
    SemaNodeView init(sema, nodeInitRef);

    SWC_ASSERT(sema.hasConstant(nodeInitRef));
    auto cst = new SymbolConstant(sema.ctx(), srcViewRef(), tokNameRef, sema.constantRefOf(nodeInitRef));

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
