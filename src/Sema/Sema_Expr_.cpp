#include "pch.h"
#include "Helpers/SemaError.h"
#include "Helpers/SemaNodeView.h"
#include "Parser/AstNodes.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaMatch.h"
#include "Symbol/IdentifierManager.h"
#include "Symbol/LookUpContext.h"
#include "Symbol/Symbol.h"
#include "Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstParenExpr::semaPostNode(Sema& sema)
{
    sema.semaInherit(*this, nodeExprRef);
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstIdentifier::semaPostNode(Sema& sema) const
{
    // Can be forced to false in case of an identifier inside a #defined
    // @CompilerNotDefined
    if (sema.hasConstant(sema.curNodeRef()))
        return AstVisitStepResult::Continue;

    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokRef());

    LookUpContext lookUpCxt;
    lookUpCxt.srcViewRef = srcViewRef();
    lookUpCxt.tokRef     = tokRef();

    const AstVisitStepResult ret = SemaMatch::match(sema, lookUpCxt, idRef);
    if (ret == AstVisitStepResult::Pause && hasParserFlag(InCompilerDefined))
        return sema.waitCompilerDefined(idRef);
    if (ret != AstVisitStepResult::Continue)
        return ret;
    sema.setSymbol(sema.curNodeRef(), lookUpCxt.first());
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstMemberAccessExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeRightRef)
        return AstVisitStepResult::Continue;

    const SemaNodeView nodeLeftView(sema, nodeLeftRef);
    const SemaNodeView nodeRightView(sema, nodeRightRef);
    TokenRef           tokNameRef;

    if (nodeRightView.node->is(AstNodeId::Identifier))
        tokNameRef = nodeRightView.node->tokRef();
    else
        SWC_UNREACHABLE();

    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokNameRef);

    // Namespace
    if (nodeLeftView.sym && nodeLeftView.sym->isNamespace())
    {
        const SymbolNamespace& namespaceSym = nodeLeftView.sym->cast<SymbolNamespace>();

        LookUpContext lookUpCxt;
        lookUpCxt.srcViewRef = srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = &namespaceSym;

        const AstVisitStepResult ret = SemaMatch::match(sema, lookUpCxt, idRef);
        if (ret != AstVisitStepResult::Continue)
            return ret;
        sema.semaInfo().setSymbol(sema.curNodeRef(), lookUpCxt.first());
        return AstVisitStepResult::SkipChildren;
    }

    // Enum
    if (nodeLeftView.type && nodeLeftView.type->isEnum())
    {
        const SymbolEnum& enumSym = nodeLeftView.type->enumSym();
        if (!enumSym.isComplete())
            return sema.waitComplete(&enumSym);

        LookUpContext lookUpCxt;
        lookUpCxt.srcViewRef = srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = &enumSym;

        const AstVisitStepResult ret = SemaMatch::match(sema, lookUpCxt, idRef);
        if (ret != AstVisitStepResult::Continue)
            return ret;
        sema.semaInfo().setSymbol(sema.curNodeRef(), lookUpCxt.first());
        return AstVisitStepResult::SkipChildren;
    }

    SemaError::raiseInternal(sema, *this);
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
