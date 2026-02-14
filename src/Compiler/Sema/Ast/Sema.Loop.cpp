#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result foreachElementTypes(Sema& sema, const AstForeachStmt& node, const SemaNodeView& exprView, TypeRef& valueTypeRef, TypeRef& indexTypeRef)
    {
        if (!exprView.type)
            return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, exprView.nodeRef);

        if (exprView.type->isArray())
            valueTypeRef = exprView.type->payloadArrayElemTypeRef();
        else if (exprView.type->isSlice())
            valueTypeRef = exprView.type->payloadTypeRef();
        else if (exprView.type->isAnyString())
            valueTypeRef = sema.typeMgr().typeU8();
        else if (exprView.type->isVariadic())
            valueTypeRef = sema.typeMgr().typeAny();
        else if (exprView.type->isTypedVariadic())
            valueTypeRef = exprView.type->payloadTypeRef();
        else
            return SemaError::raiseTypeNotIndexable(sema, exprView.nodeRef, exprView.typeRef);

        indexTypeRef = sema.typeMgr().typeU64();

        if (node.hasFlag(AstForeachStmtFlagsE::ByAddress))
        {
            TypeInfoFlags typeFlags = TypeInfoFlagsE::Zero;
            if (exprView.type->isConst())
                typeFlags.add(TypeInfoFlagsE::Const);
            valueTypeRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(valueTypeRef, typeFlags));
        }

        return Result::Continue;
    }
}

Result AstForCStyleStmt::semaPreNode(Sema& sema)
{
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    return Result::Continue;
}

Result AstForCStyleStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodePostStmtRef || (childRef == nodeBodyRef && nodePostStmtRef.isInvalid()))
    {
        SemaFrame frame = sema.frame();
        frame.setCurrentBreakContent(sema.curNodeRef(), SemaFrame::BreakContextKind::Loop);
        sema.pushFramePopOnPostNode(frame);
    }

    return Result::Continue;
}

Result AstForCStyleStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeExprRef)
    {
        SemaNodeView nodeView(sema, nodeExprRef);
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeView.nodeRef));
        RESULT_VERIFY(Cast::cast(sema, nodeView, sema.typeMgr().typeBool(), CastKind::Condition));
    }

    return Result::Continue;
}

Result AstForStmt::semaPreNode(Sema& sema) const
{
    return SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Reverse);
}

Result AstForeachStmt::semaPreNode(Sema& sema) const
{
    return SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Reverse);
}

Result AstForeachStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeWhereRef || (childRef == nodeBodyRef && nodeWhereRef.isInvalid()))
    {
        SemaFrame frame = sema.frame();
        frame.setCurrentBreakContent(sema.curNodeRef(), SemaFrame::BreakContextKind::Loop);
        sema.pushFramePopOnPostNode(frame);
        sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);

        // Alias names
        SmallVector<TokenRef> tokNames;
        sema.ast().appendTokens(tokNames, spanNamesRef);
        if (!tokNames.empty())
        {
            if (tokNames.size() > 2)
                return SemaError::raise(sema, DiagnosticId::sema_err_foreach_too_many_names, SourceCodeRef{srcViewRef(), tokNames[2]});

            const SemaNodeView exprView(sema, nodeExprRef);
            TypeRef            valueTypeRef = TypeRef::invalid();
            TypeRef            indexTypeRef = TypeRef::invalid();
            RESULT_VERIFY(foreachElementTypes(sema, *this, exprView, valueTypeRef, indexTypeRef));

            SmallVector<Symbol*> symbols;
            symbols.reserve(tokNames.size());

            const size_t count = std::min<size_t>(tokNames.size(), 2);
            for (size_t i = 0; i < count; i++)
            {
                const auto tokNameRef = tokNames[i];
                if (tokNameRef.isInvalid())
                    continue;

                SymbolVariable& symVar = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
                symVar.registerAttributes(sema);
                symVar.setDeclared(sema.ctx());
                RESULT_VERIFY(Match::ghosting(sema, symVar));

                symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
                symVar.setTypeRef(i == 0 ? valueTypeRef : indexTypeRef);
                symVar.setTyped(sema.ctx());
                symVar.setSemaCompleted(sema.ctx());
                symbols.push_back(&symVar);
            }

            if (!symbols.empty())
                sema.setSymbolList(sema.curNodeRef(), symbols.span());
        }
    }

    return Result::Continue;
}

Result AstForeachStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeExprRef)
    {
        const SemaNodeView exprView(sema, nodeExprRef);
        RESULT_VERIFY(SemaCheck::isValue(sema, exprView.nodeRef));

        TypeRef valueTypeRef = TypeRef::invalid();
        TypeRef indexTypeRef = TypeRef::invalid();
        RESULT_VERIFY(foreachElementTypes(sema, *this, exprView, valueTypeRef, indexTypeRef));
    }

    if (childRef == nodeWhereRef)
    {
        SemaNodeView nodeView(sema, nodeWhereRef);
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeView.nodeRef));
        RESULT_VERIFY(Cast::cast(sema, nodeView, sema.typeMgr().typeBool(), CastKind::Condition));
    }

    return Result::Continue;
}

Result AstForStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    // Body has its own local scope.
    if (childRef == nodeWhereRef || (childRef == nodeBodyRef && nodeWhereRef.isInvalid()))
    {
        SemaFrame frame = sema.frame();
        frame.setCurrentBreakContent(sema.curNodeRef(), SemaFrame::BreakContextKind::Loop);
        sema.pushFramePopOnPostNode(frame);
        sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);

        // Create a variable
        if (tokNameRef.isValid())
        {
            auto& symVar = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
            symVar.registerAttributes(sema);
            symVar.setDeclared(sema.ctx());
            RESULT_VERIFY(Match::ghosting(sema, symVar));

            const SemaNodeView nodeView(sema, nodeExprRef);
            symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
            symVar.setTypeRef(nodeView.typeRef);
            symVar.setTyped(sema.ctx());
            symVar.setSemaCompleted(sema.ctx());
        }
    }

    return Result::Continue;
}

Result AstForStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeExprRef)
    {
        const SemaNodeView nodeView(sema, nodeExprRef);
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeView.nodeRef));
        if (nodeView.node->isNot(AstNodeId::RangeExpr))
        {
            const AstNode& exprNode   = sema.node(nodeExprRef);
            auto [countRef, countPtr] = sema.ast().makeNode<AstNodeId::CountOfExpr>(exprNode.tokRef());
            countPtr->nodeExprRef     = nodeExprRef;
            RESULT_VERIFY(SemaHelpers::intrinsicCountOf(sema, countRef, nodeExprRef));
            sema.setSubstitute(nodeExprRef, countRef);
        }
        else if (!nodeView.type->isInt())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_countof_type, nodeView.nodeRef);
            diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }
    }

    if (childRef == nodeWhereRef)
    {
        SemaNodeView nodeView(sema, nodeWhereRef);
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeView.nodeRef));
        RESULT_VERIFY(Cast::cast(sema, nodeView, sema.typeMgr().typeBool(), CastKind::Condition));
    }

    return Result::Continue;
}

Result AstWhileStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    // Body has its own local scope.
    if (childRef == nodeBodyRef)
    {
        SemaFrame frame = sema.frame();
        frame.setCurrentBreakContent(sema.curNodeRef(), SemaFrame::BreakContextKind::Loop);
        sema.pushFramePopOnPostChild(frame, childRef);
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);
    }

    return Result::Continue;
}

Result AstInfiniteLoopStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    // Body has its own local scope.
    if (childRef == nodeBodyRef)
    {
        SemaFrame frame = sema.frame();
        frame.setCurrentBreakContent(sema.curNodeRef(), SemaFrame::BreakContextKind::Loop);
        sema.pushFramePopOnPostChild(frame, childRef);
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);
    }

    return Result::Continue;
}

Result AstWhileStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    // Ensure while condition is `bool` (or castable to it).
    if (childRef == nodeExprRef)
    {
        SemaNodeView nodeView(sema, nodeExprRef);
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeView.nodeRef));
        RESULT_VERIFY(Cast::cast(sema, nodeView, sema.typeMgr().typeBool(), CastKind::Condition));
    }

    return Result::Continue;
}

Result AstBreakStmt::semaPreNode(Sema& sema)
{
    if (sema.frame().currentBreakableKind() == SemaFrame::BreakContextKind::None)
        return SemaError::raise(sema, DiagnosticId::sema_err_break_outside_breakable, sema.curNodeRef());
    return Result::Continue;
}

Result AstContinueStmt::semaPreNode(Sema& sema)
{
    if (sema.frame().currentBreakableKind() == SemaFrame::BreakContextKind::None)
        return SemaError::raise(sema, DiagnosticId::sema_err_continue_outside_breakable, sema.curNodeRef());
    if (sema.frame().currentBreakableKind() != SemaFrame::BreakContextKind::Loop)
        return SemaError::raise(sema, DiagnosticId::sema_err_continue_not_in_loop, sema.curNodeRef());
    return Result::Continue;
}

SWC_END_NAMESPACE();
