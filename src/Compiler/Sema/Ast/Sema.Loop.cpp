#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Loop.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint64_t enumValueCount(const SymbolEnum& symEnum)
    {
        std::vector<const Symbol*> symbols;
        symEnum.getAllSymbols(symbols);

        uint64_t result = 0;
        for (const Symbol* symbol : symbols)
        {
            if (symbol && symbol->isEnumValue())
                result += 1;
        }

        return result;
    }

    LoopSemaPayload& ensureLoopSemaPayload(Sema& sema, AstNodeRef nodeRef)
    {
        if (auto* payload = sema.semaPayload<LoopSemaPayload>(nodeRef))
            return *payload;

        auto* payload = sema.compiler().allocate<LoopSemaPayload>();
        sema.setSemaPayload(nodeRef, payload);
        return *payload;
    }

    Result resolveForStmtIndexTypeRef(Sema& sema, TypeRef& outTypeRef, AstNodeRef forRef, const AstForStmt& node)
    {
        outTypeRef = TypeRef::invalid();
        if (sema.node(node.nodeExprRef).is(AstNodeId::RangeExpr))
        {
            outTypeRef = sema.viewType(node.nodeExprRef).typeRef();
            return Result::Continue;
        }

        if (const auto* payload = sema.semaPayload<LoopSemaPayload>(forRef))
        {
            outTypeRef = payload->indexTypeRef;
            return Result::Continue;
        }

        SemaHelpers::CountOfResultInfo countResult;
        SWC_RESULT(SemaHelpers::resolveCountOfResult(sema, countResult, node.nodeExprRef));
        outTypeRef = countResult.typeRef;
        return Result::Continue;
    }

    TypeRef foreachInternalArrayType(Sema& sema, TypeRef elemTypeRef, uint64_t count)
    {
        SmallVector<uint64_t> dims;
        dims.push_back(count);
        return sema.typeMgr().addType(TypeInfo::makeArray(dims.span(), elemTypeRef));
    }

    const SymbolEnum* enumTypeExprSymbol(Sema& sema, const SemaNodeView& exprView)
    {
        if (exprView.type() && exprView.type()->isEnum())
            return &exprView.type()->payloadSymEnum();

        const SemaNodeView symView = sema.viewSymbol(exprView.nodeRef());
        if (symView.sym() && symView.sym()->isEnum())
            return &symView.sym()->cast<SymbolEnum>();

        return nullptr;
    }

    bool isEnumTypeExpr(Sema& sema, const SemaNodeView& exprView)
    {
        return enumTypeExprSymbol(sema, exprView) != nullptr;
    }

    Result validateForeachAliasCount(Sema& sema, const AstForeachStmt& node)
    {
        SmallVector<TokenRef> tokNames;
        sema.ast().appendTokens(tokNames, node.spanNamesRef);
        if (tokNames.size() <= 2)
            return Result::Continue;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_foreach_too_many_names, SourceCodeRef{node.srcViewRef(), tokNames[2]});
        diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(tokNames.size()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    void pushLoopFrame(Sema& sema, AstNodeRef loopRef, TypeRef indexTypeRef)
    {
        SemaFrame frame = sema.frame();
        frame.setCurrentBreakContent(loopRef, SemaFrame::BreakContextKind::Loop);
        frame.setCurrentLoopIndexTypeRef(indexTypeRef);
        frame.setCurrentLoopIndexOwnerRef(loopRef);
        sema.pushFramePopOnPostNode(frame);
    }

    Result ensureLoopLocalStorage(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
    {
        SemaHelpers::ensureCurrentLocalScopeSymbol(sema, &symVar);
        return SemaHelpers::ensureRuntimeStorageDeclaredAndCompleted(sema, symVar, typeRef);
    }

    template<typename F>
    SymbolVariable& getOrCreateLoopLocalSymbol(LoopSemaPayload& payload, size_t index, F&& createSymbol)
    {
        if (payload.localSymbols.size() > index)
            return payload.localSymbols[index]->cast<SymbolVariable>();

        SWC_ASSERT(payload.localSymbols.size() == index);
        auto& symVar = createSymbol();
        payload.localSymbols.push_back(&symVar);
        return symVar;
    }

    Result appendForeachAliasSymbols(Sema& sema, SmallVector<Symbol*>& outSymbols, LoopSemaPayload& payload, const AstForeachStmt& node, TypeRef valueTypeRef, TypeRef indexTypeRef)
    {
        SmallVector<TokenRef> tokNames;
        sema.ast().appendTokens(tokNames, node.spanNamesRef);

        const size_t count = std::min<size_t>(tokNames.size(), 2);
        size_t       index = 0;
        for (size_t i = 0; i < count; ++i)
        {
            const TokenRef tokNameRef = tokNames[i];
            if (tokNameRef.isInvalid())
                continue;

            auto& symVar = getOrCreateLoopLocalSymbol(payload, index, [&]() -> SymbolVariable& {
                return SemaHelpers::registerSymbol<SymbolVariable>(sema, node, tokNameRef);
            });
            SWC_RESULT(ensureLoopLocalStorage(sema, symVar, index == 0 ? valueTypeRef : indexTypeRef));
            outSymbols.push_back(&symVar);
            index += 1;
        }

        return Result::Continue;
    }

    Result foreachElementTypes(Sema& sema, const AstForeachStmt& node, const SemaNodeView& exprView, TypeRef& valueTypeRef, TypeRef& indexTypeRef)
    {
        bool sourceIsConst = false;
        bool sourceIsEnum  = false;

        if (const SymbolEnum* symEnum = enumTypeExprSymbol(sema, exprView))
        {
            valueTypeRef = symEnum->typeRef();
            indexTypeRef = sema.typeMgr().typeU64();
            sourceIsEnum = true;
        }
        else
        {
            if (!exprView.type())
                return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, exprView.nodeRef());

            if (exprView.type()->isArray())
                valueTypeRef = exprView.type()->payloadArrayElemTypeRef();
            else if (exprView.type()->isSlice())
                valueTypeRef = exprView.type()->payloadTypeRef();
            else if (exprView.type()->isAnyString())
                valueTypeRef = sema.typeMgr().typeU8();
            else if (exprView.type()->isVariadic())
                valueTypeRef = sema.typeMgr().typeAny();
            else if (exprView.type()->isTypedVariadic())
                valueTypeRef = exprView.type()->payloadTypeRef();
            else
                return SemaError::raiseTypeNotIndexable(sema, exprView.nodeRef(), exprView.typeRef());

            indexTypeRef  = sema.typeMgr().typeU64();
            sourceIsConst = exprView.type()->isConst();
        }

        if (node.hasFlag(AstForeachStmtFlagsE::ByAddress))
        {
            TypeInfoFlags typeFlags = TypeInfoFlagsE::Zero;
            if (sourceIsConst || sourceIsEnum)
                typeFlags.add(TypeInfoFlagsE::Const);
            valueTypeRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(valueTypeRef, typeFlags));
        }

        return Result::Continue;
    }
}

Result AstForCStyleStmt::semaPreNode(Sema& sema)
{
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    const auto& forNode = sema.curNode().cast<AstForCStyleStmt>();

    SmallVector<Symbol*> symbols;
    auto&                stateSym = SemaHelpers::registerUniqueSymbol<SymbolVariable>(sema, forNode, "for_index_state");
    SWC_RESULT(SemaHelpers::declareGhostAndCompleteStorage(sema, stateSym, sema.typeMgr().typeU64()));
    symbols.push_back(&stateSym);
    sema.setSymbolList(sema.curNodeRef(), symbols.span());
    return Result::Continue;
}

Result AstForCStyleStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodePostStmtRef || (childRef == nodeBodyRef && nodePostStmtRef.isInvalid()))
        pushLoopFrame(sema, sema.curNodeRef(), sema.typeMgr().typeU64());

    return Result::Continue;
}

Result AstForCStyleStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeExprRef)
    {
        SemaNodeView view = sema.viewNodeTypeConstant(nodeExprRef);
        SWC_RESULT(SemaCheck::isValue(sema, view.nodeRef()));
        SWC_RESULT(Cast::cast(sema, view, sema.typeMgr().typeBool(), CastKind::BoolExpr));
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
    if (const auto* payload = sema.semaPayload<LoopSemaPayload>(sema.curNodeRef());
        payload &&
        payload->usesCustomVisit &&
        (childRef == nodeWhereRef || childRef == nodeBodyRef))
        return Result::SkipChildren;

    if (childRef == nodeWhereRef || (childRef == nodeBodyRef && nodeWhereRef.isInvalid()))
    {
        SWC_RESULT(validateForeachAliasCount(sema, *this));

        const SemaNodeView exprView     = sema.viewType(nodeExprRef);
        TypeRef            valueTypeRef = TypeRef::invalid();
        TypeRef            indexTypeRef = TypeRef::invalid();
        auto&              payload      = ensureLoopSemaPayload(sema, sema.curNodeRef());
        SWC_RESULT(foreachElementTypes(sema, *this, exprView, valueTypeRef, indexTypeRef));

        pushLoopFrame(sema, sema.curNodeRef(), indexTypeRef);
        sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
        SmallVector<Symbol*> symbols;
        symbols.reserve(4);
        SWC_RESULT(appendForeachAliasSymbols(sema, symbols, payload, *this, valueTypeRef, indexTypeRef));

        const size_t stateIndex = symbols.size();
        auto& stateSym          = getOrCreateLoopLocalSymbol(payload, stateIndex, [&]() -> SymbolVariable& {
            return SemaHelpers::registerUniqueSymbol<SymbolVariable>(sema, *this, "foreach_state");
        });
        SWC_RESULT(ensureLoopLocalStorage(sema, stateSym, foreachInternalArrayType(sema, sema.typeMgr().typeU64(), 3)));
        symbols.push_back(&stateSym);

        auto& sourceSpillSym = getOrCreateLoopLocalSymbol(payload, stateIndex + 1, [&]() -> SymbolVariable& {
            return SemaHelpers::registerUniqueSymbol<SymbolVariable>(sema, *this, "foreach_source_spill");
        });
        SWC_RESULT(ensureLoopLocalStorage(sema, sourceSpillSym, foreachInternalArrayType(sema, sema.typeMgr().typeU8(), 8)));
        symbols.push_back(&sourceSpillSym);

        SWC_ASSERT(payload.localSymbols.size() == symbols.size());
        sema.setSymbolList(sema.curNodeRef(), payload.localSymbols.span());
    }

    return Result::Continue;
}

Result AstForeachStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeExprRef)
    {
        SWC_RESULT(validateForeachAliasCount(sema, *this));

        bool canResolveVisit = false;
        SWC_RESULT(SemaSpecOp::canResolveVisit(sema, *this, canResolveVisit));
        if (canResolveVisit)
        {
            ensureLoopSemaPayload(sema, sema.curNodeRef()).usesCustomVisit = true;
            return Result::Continue;
        }

        const SemaNodeView exprView = sema.viewType(nodeExprRef);
        if (!isEnumTypeExpr(sema, exprView))
            SWC_RESULT(SemaCheck::isValue(sema, exprView.nodeRef()));

        TypeRef valueTypeRef = TypeRef::invalid();
        TypeRef indexTypeRef = TypeRef::invalid();
        SWC_RESULT(foreachElementTypes(sema, *this, exprView, valueTypeRef, indexTypeRef));
    }

    if (childRef == nodeWhereRef)
    {
        SemaNodeView view = sema.viewNodeTypeConstant(nodeWhereRef);
        SWC_RESULT(SemaCheck::isValue(sema, view.nodeRef()));
        SWC_RESULT(Cast::cast(sema, view, sema.typeMgr().typeBool(), CastKind::BoolExpr));
    }

    return Result::Continue;
}

Result AstForeachStmt::semaPostNode(Sema& sema) const
{
    const auto* payload = sema.semaPayload<LoopSemaPayload>(sema.curNodeRef());
    if (!payload || !payload->usesCustomVisit)
        return Result::Continue;

    bool handled = false;
    SWC_RESULT(SemaSpecOp::tryResolveVisit(sema, *this, handled));
    SWC_ASSERT(handled);
    return Result::Continue;
}

Result AstForStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    // Body has its own local scope.
    if (childRef == nodeWhereRef || (childRef == nodeBodyRef && nodeWhereRef.isInvalid()))
    {
        TypeRef indexTypeRef = TypeRef::invalid();
        SWC_RESULT(resolveForStmtIndexTypeRef(sema, indexTypeRef, sema.curNodeRef(), *this));

        pushLoopFrame(sema, sema.curNodeRef(), indexTypeRef);
        sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);

        // Create a variable
        if (tokNameRef.isValid())
        {
            auto&   symVar   = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
            TypeRef indexRef = TypeRef::invalid();
            SWC_RESULT(resolveForStmtIndexTypeRef(sema, indexRef, sema.curNodeRef(), *this));
            SWC_RESULT(SemaHelpers::declareGhostAndCompleteStorage(sema, symVar, indexRef));
        }
    }

    return Result::Continue;
}

Result AstForStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeExprRef)
    {
        const SemaNodeView view = sema.viewNodeType(nodeExprRef);
        if (const SymbolEnum* symEnum = enumTypeExprSymbol(sema, view))
        {
            SWC_RESULT(sema.waitSemaCompleted(symEnum, view.node()->codeRef()));

            auto& payload        = ensureLoopSemaPayload(sema, sema.curNodeRef());
            payload.indexTypeRef = sema.typeMgr().typeU64();
            payload.countCstRef  = sema.cstMgr().addInt(sema.ctx(), enumValueCount(*symEnum));
        }
        else
        {
            SWC_RESULT(SemaCheck::isValue(sema, view.nodeRef()));
            if (view.node()->isNot(AstNodeId::RangeExpr))
            {
                SemaHelpers::CountOfResultInfo countResult;
                SWC_RESULT(SemaHelpers::resolveCountOfResult(sema, countResult, nodeExprRef));
                auto& payload        = ensureLoopSemaPayload(sema, sema.curNodeRef());
                payload.indexTypeRef = countResult.typeRef;
                payload.countCstRef  = countResult.cstRef;
                payload.countFn      = countResult.calledFn;
                if (countResult.calledFn != nullptr)
                {
                    payload.countResolvedArgs.clear();
                    sema.appendResolvedCallArguments(sema.curNodeRef(), payload.countResolvedArgs);

                    // A loop statement is not the count expression itself. Restore it to statement
                    // semantics after borrowing the synthetic call metadata for `opCount`.
                    sema.setType(sema.curNodeRef(), sema.typeMgr().typeVoid());
                    sema.unsetIsValue(sema.curNodeRef());
                    sema.unsetIsLValue(sema.curNodeRef());
                    sema.unsetFoldedTypedConst(sema.curNodeRef());
                }
            }
            else if (!view.type()->isInt())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_countof_type, view.nodeRef());
                diag.addArgument(Diagnostic::ARG_TYPE, view.typeRef());
                diag.report(sema.ctx());
                return Result::Error;
            }
            else
            {
                const auto& rangeExpr = sema.node(nodeExprRef).cast<AstRangeExpr>();
                auto&       payload   = ensureLoopSemaPayload(sema, sema.curNodeRef());
                payload.isRangeLoop   = true;
                payload.indexTypeRef  = view.typeRef();
                payload.inclusive     = rangeExpr.hasFlag(AstRangeExprFlagsE::Inclusive);
                payload.lowerBoundRef = rangeExpr.nodeExprDownRef;
                payload.upperBoundRef = rangeExpr.nodeExprUpRef;
            }
        }
    }

    if (childRef == nodeWhereRef)
    {
        SemaNodeView view = sema.viewNodeTypeConstant(nodeWhereRef);
        SWC_RESULT(SemaCheck::isValue(sema, view.nodeRef()));
        SWC_RESULT(Cast::cast(sema, view, sema.typeMgr().typeBool(), CastKind::BoolExpr));
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
        frame.setCurrentLoopIndexTypeRef(sema.typeMgr().typeU64());
        frame.setCurrentLoopIndexOwnerRef(sema.curNodeRef());
        sema.pushFramePopOnPostChild(frame, childRef);
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);

        SmallVector<Symbol*> symbols;
        auto&                stateSym = SemaHelpers::registerUniqueSymbol<SymbolVariable>(sema, *this, "for_index_state");
        SWC_RESULT(SemaHelpers::declareGhostAndCompleteStorage(sema, stateSym, sema.typeMgr().typeU64()));
        symbols.push_back(&stateSym);
        sema.setSymbolList(sema.curNodeRef(), symbols.span());
    }

    return Result::Continue;
}

Result AstWhileStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    // Ensure while condition is `bool` (or castable to it).
    if (childRef == nodeExprRef)
    {
        SemaNodeView view = sema.viewNodeTypeConstant(nodeExprRef);
        SWC_RESULT(SemaCheck::isValue(sema, view.nodeRef()));
        SWC_RESULT(Cast::cast(sema, view, sema.typeMgr().typeBool(), CastKind::BoolExpr));
    }

    return Result::Continue;
}

Result AstBreakStmt::semaPreNode(Sema& sema)
{
    if (sema.frame().currentBreakableKind() == SemaFrame::BreakContextKind::None)
        return SemaError::raise(sema, DiagnosticId::sema_err_break_outside_breakable, sema.curNodeRef());
    return Result::Continue;
}

Result AstUnreachableStmt::semaPreNode(Sema& sema)
{
    return SemaHelpers::setupRuntimeSafetyPanic(sema, sema.curNodeRef(), Runtime::SafetyWhat::Unreachable, sema.curNode().codeRef());
}

Result AstContinueStmt::semaPreNode(Sema& sema)
{
    if (sema.frame().currentBreakableKind() == SemaFrame::BreakContextKind::None)
        return SemaError::raise(sema, DiagnosticId::sema_err_continue_outside_breakable, sema.curNodeRef());
    if (sema.frame().currentBreakableKind() != SemaFrame::BreakContextKind::Loop &&
        sema.frame().currentBreakableKind() != SemaFrame::BreakContextKind::Scope)
        return SemaError::raise(sema, DiagnosticId::sema_err_continue_not_in_loop, sema.curNodeRef());
    return Result::Continue;
}

SWC_END_NAMESPACE();
