#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/IdentifierManager.h"
#include "Sema/Symbol/LookUpContext.h"
#include "Sema/Symbol/SemaMatch.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

AstStepResult AstParenExpr::semaPostNode(Sema& sema)
{
    sema.semaInherit(*this, nodeExprRef);
    return AstStepResult::Continue;
}

AstStepResult AstIdentifier::semaPostNode(Sema& sema) const
{
    // Can be forced to false in case of an identifier inside a #defined
    // @CompilerNotDefined
    if (sema.hasConstant(sema.curNodeRef()))
        return AstStepResult::Continue;

    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokRef());

    LookUpContext lookUpCxt;
    lookUpCxt.srcViewRef = srcViewRef();
    lookUpCxt.tokRef     = tokRef();

    const AstStepResult ret = SemaMatch::match(sema, lookUpCxt, idRef);
    if (ret == AstStepResult::Pause && hasParserFlag(InCompilerDefined))
        return sema.waitCompilerDefined(idRef, srcViewRef(), tokRef());
    if (ret != AstStepResult::Continue)
        return ret;
    sema.setSymbol(sema.curNodeRef(), lookUpCxt.first());
    return AstStepResult::Continue;
}

AstStepResult AstMemberAccessExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeRightRef)
        return AstStepResult::Continue;

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

        const AstStepResult ret = SemaMatch::match(sema, lookUpCxt, idRef);
        if (ret != AstStepResult::Continue)
            return ret;

        sema.semaInfo().setSymbol(nodeRightRef, lookUpCxt.first());
        sema.semaInfo().setSymbol(sema.curNodeRef(), lookUpCxt.first());
        return AstStepResult::SkipChildren;
    }

    // Enum
    if (nodeLeftView.type && nodeLeftView.type->isEnum())
    {
        const SymbolEnum& enumSym = nodeLeftView.type->enumSym();
        if (!enumSym.isCompleted())
            return sema.waitCompleted(&enumSym, srcViewRef(), tokNameRef);

        LookUpContext lookUpCxt;
        lookUpCxt.srcViewRef = srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = &enumSym;

        const AstStepResult ret = SemaMatch::match(sema, lookUpCxt, idRef);
        if (ret != AstStepResult::Continue)
            return ret;

        sema.semaInfo().setSymbol(nodeRightRef, lookUpCxt.first());
        sema.semaInfo().setSymbol(sema.curNodeRef(), lookUpCxt.first());
        return AstStepResult::SkipChildren;
    }

    // Struct
    if (nodeLeftView.type && nodeLeftView.type->isStruct())
    {
        const SymbolStruct& symStruct = nodeLeftView.type->structSym();
        if (!symStruct.isCompleted())
            return sema.waitCompleted(&symStruct, srcViewRef(), tokNameRef);

        LookUpContext lookUpCxt;
        lookUpCxt.srcViewRef = srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = &symStruct;

        const AstStepResult ret = SemaMatch::match(sema, lookUpCxt, idRef);
        if (ret != AstStepResult::Continue)
            return ret;

        sema.semaInfo().setSymbol(nodeRightRef, lookUpCxt.first());
        sema.semaInfo().setSymbol(sema.curNodeRef(), lookUpCxt.first());
        return AstStepResult::SkipChildren;
    }

    // Interface
    if (nodeLeftView.type && nodeLeftView.type->isInterface())
    {
        const SymbolInterface& symInterface = nodeLeftView.type->interfaceSym();
        if (!symInterface.isCompleted())
            return sema.waitCompleted(&symInterface, srcViewRef(), tokNameRef);
        // TODO
        return AstStepResult::SkipChildren;
    }

    return SemaError::raiseInternal(sema, *this);
}

AstStepResult AstCompilerRunExpr::semaPreNode(Sema& sema)
{
    // TODO
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(true));
    return AstStepResult::SkipChildren;
}

SWC_END_NAMESPACE()
