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

Result AstParenExpr::semaPostNode(Sema& sema)
{
    sema.semaInherit(*this, nodeExprRef);
    return Result::Continue;
}

Result AstIdentifier::semaPostNode(Sema& sema) const
{
    // Can be forced to false in case of an identifier inside a #defined
    // @CompilerNotDefined
    if (sema.hasConstant(sema.curNodeRef()))
        return Result::Continue;

    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokRef());

    LookUpContext lookUpCxt;
    lookUpCxt.srcViewRef = srcViewRef();
    lookUpCxt.tokRef     = tokRef();

    const Result ret = SemaMatch::match(sema, lookUpCxt, idRef);
    if (ret == Result::Pause && hasParserFlag(InCompilerDefined))
        return sema.waitCompilerDefined(idRef, srcViewRef(), tokRef());
    if (ret != Result::Continue)
        return ret;
    sema.setSymbol(sema.curNodeRef(), lookUpCxt.first());
    return Result::Continue;
}

Result AstMemberAccessExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeRightRef)
        return Result::Continue;

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

        const Result ret = SemaMatch::match(sema, lookUpCxt, idRef);
        if (ret != Result::Continue)
            return ret;

        sema.semaInfo().setSymbol(nodeRightRef, lookUpCxt.first());
        sema.semaInfo().setSymbol(sema.curNodeRef(), lookUpCxt.first());
        return Result::SkipChildren;
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

        const Result ret = SemaMatch::match(sema, lookUpCxt, idRef);
        if (ret != Result::Continue)
            return ret;

        sema.semaInfo().setSymbol(nodeRightRef, lookUpCxt.first());
        sema.semaInfo().setSymbol(sema.curNodeRef(), lookUpCxt.first());
        return Result::SkipChildren;
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

        const Result ret = SemaMatch::match(sema, lookUpCxt, idRef);
        if (ret != Result::Continue)
            return ret;

        sema.semaInfo().setSymbol(nodeRightRef, lookUpCxt.first());
        sema.semaInfo().setSymbol(sema.curNodeRef(), lookUpCxt.first());
        return Result::SkipChildren;
    }

    // Interface
    if (nodeLeftView.type && nodeLeftView.type->isInterface())
    {
        const SymbolInterface& symInterface = nodeLeftView.type->interfaceSym();
        if (!symInterface.isCompleted())
            return sema.waitCompleted(&symInterface, srcViewRef(), tokNameRef);
        // TODO
        return Result::SkipChildren;
    }

    return SemaError::raiseInternal(sema, *this);
}

Result AstCompilerRunExpr::semaPreNode(Sema& sema)
{
    // TODO
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(true));
    return Result::SkipChildren;
}

SWC_END_NAMESPACE()
