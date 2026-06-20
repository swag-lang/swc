#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Constant.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct IfVarDeclWhereSemaPayload
    {
        Symbol*     maskedConditionSymbol = nullptr;
        ConstantRef maskedConditionCstRef = ConstantRef::invalid();
    };

    struct IfStmtNonNullGuardPayload
    {
        const Symbol* thenSymbol = nullptr;
        const Symbol* elseSymbol = nullptr;
    };

    IfStmtNonNullGuardPayload& ensureIfStmtNonNullGuardPayload(Sema& sema, AstNodeRef nodeRef)
    {
        if (auto* payload = sema.semaPayload<IfStmtNonNullGuardPayload>(nodeRef))
            return *payload;

        auto* payload = sema.compiler().allocate<IfStmtNonNullGuardPayload>();
        sema.setSemaPayload(nodeRef, payload);
        return *payload;
    }

    IfVarDeclWhereSemaPayload& ensureIfVarDeclWhereSemaPayload(Sema& sema, AstNodeRef nodeRef)
    {
        if (auto* payload = sema.semaPayload<IfVarDeclWhereSemaPayload>(nodeRef))
            return *payload;

        auto* payload = sema.compiler().allocate<IfVarDeclWhereSemaPayload>();
        sema.setSemaPayload(nodeRef, payload);
        return *payload;
    }

    ConstantRef conditionSymbolConstantRef(const Symbol& symbol)
    {
        if (const auto* symVar = symbol.safeCast<SymbolVariable>())
            return symVar->cstRef();
        if (const auto* symConst = symbol.safeCast<SymbolConstant>())
            return symConst->cstRef();
        return ConstantRef::invalid();
    }

    void setConditionSymbolConstantRef(Symbol& symbol, ConstantRef cstRef)
    {
        if (auto* symVar = symbol.safeCast<SymbolVariable>())
        {
            symVar->setCstRef(cstRef);
            return;
        }

        if (auto* symConst = symbol.safeCast<SymbolConstant>())
        {
            symConst->setCstRef(cstRef);
            return;
        }

        SWC_UNREACHABLE();
    }

    AstNodeRef singleIfVarDeclDeclRef(Sema& sema, AstNodeRef varDeclRef)
    {
        AstNodeRef     declRef = varDeclRef;
        const AstNode& varNode = sema.node(varDeclRef);
        if (varNode.is(AstNodeId::VarDeclList))
        {
            const auto&             list = varNode.cast<AstVarDeclList>();
            SmallVector<AstNodeRef> decls;
            sema.ast().appendNodes(decls, list.spanChildrenRef);
            if (decls.size() != 1)
                return AstNodeRef::invalid();
            declRef = decls.front();
        }

        return declRef;
    }

    bool ifVarDeclUsesLetBinding(Sema& sema, AstNodeRef varDeclRef)
    {
        const AstNodeRef declRef = singleIfVarDeclDeclRef(sema, varDeclRef);
        if (declRef.isInvalid())
            return false;

        const AstNode& declNode = sema.node(declRef);
        if (const auto* singleDecl = declNode.safeCast<AstSingleVarDecl>())
            return singleDecl->hasFlag(AstVarDeclFlagsE::Let);
        if (const auto* multiDecl = declNode.safeCast<AstMultiVarDecl>())
            return multiDecl->hasFlag(AstVarDeclFlagsE::Let);
        return false;
    }

    bool singleIfVarDeclConditionSymbol(Sema& sema, AstNodeRef varDeclRef, Symbol*& outSym)
    {
        outSym = nullptr;

        const AstNodeRef declRef = singleIfVarDeclDeclRef(sema, varDeclRef);
        if (declRef.isInvalid())
            return false;

        const SemaNodeView declView = sema.view(declRef, SemaNodeViewPartE::Symbol);
        Symbol*            symbol   = declView.singleSymbol();
        if (!symbol)
            return false;

        outSym = symbol;
        return true;
    }

    bool ifVarDeclNeedsWhereShortCircuit(Sema& sema, AstNodeRef varDeclRef)
    {
        if (!ifVarDeclUsesLetBinding(sema, varDeclRef))
            return false;

        Symbol* conditionSym = nullptr;
        if (!singleIfVarDeclConditionSymbol(sema, varDeclRef, conditionSym))
            return false;

        const TypeRef typeRef = conditionSym->typeRef();
        if (typeRef.isInvalid())
            return false;

        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        return typeInfo.isPointerLikeAliasAware(sema.ctx()) || typeInfo.isNull();
    }

    void restoreMaskedIfVarDeclCondition(const Sema& sema, AstNodeRef nodeRef)
    {
        auto* payload = sema.semaPayload<IfVarDeclWhereSemaPayload>(nodeRef);
        if (!payload || !payload->maskedConditionSymbol)
            return;

        setConditionSymbolConstantRef(*payload->maskedConditionSymbol, payload->maskedConditionCstRef);
        *payload = {};
    }

    void maybeMaskIfVarDeclConditionForWhere(Sema& sema, AstNodeRef ifRef, AstNodeRef varDeclRef)
    {
        Symbol* conditionSym = nullptr;
        if (!singleIfVarDeclConditionSymbol(sema, varDeclRef, conditionSym))
            return;

        const ConstantRef conditionCstRef = conditionSymbolConstantRef(*conditionSym);
        if (conditionCstRef.isInvalid())
            return;

        auto& payload                 = ensureIfVarDeclWhereSemaPayload(sema, ifRef);
        payload.maskedConditionSymbol = conditionSym;
        payload.maskedConditionCstRef = conditionCstRef;
        setConditionSymbolConstantRef(*conditionSym, ConstantRef::invalid());
    }

    void storeIfStmtNonNullGuard(Sema& sema, AstNodeRef ifRef, AstNodeRef conditionRef)
    {
        const SemaHelpers::NullableGuardInfo guard = SemaHelpers::nullableGuardInfo(sema, conditionRef);
        if (!guard.symbol)
            return;

        auto& payload = ensureIfStmtNonNullGuardPayload(sema, ifRef);
        if (guard.nonNullWhenTrue)
            payload.thenSymbol = guard.symbol;
        else
            payload.elseSymbol = guard.symbol;
    }

    const Symbol* ifStmtNonNullGuardSymbol(const Sema& sema, AstNodeRef ifRef, AstNodeRef childRef, AstNodeRef thenRef, AstNodeRef elseRef)
    {
        const auto* payload = sema.semaPayload<IfStmtNonNullGuardPayload>(ifRef);
        if (!payload)
            return nullptr;
        if (childRef == thenRef)
            return payload->thenSymbol;
        if (childRef == elseRef)
            return payload->elseSymbol;
        return nullptr;
    }

    bool nodeStopsLocalFlow(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return false;

        const AstNode& node = sema.node(nodeRef);
        switch (node.id())
        {
            case AstNodeId::ReturnStmt:
            case AstNodeId::BreakStmt:
            case AstNodeId::ContinueStmt:
            case AstNodeId::FallThroughStmt:
            case AstNodeId::UnreachableStmt:
            case AstNodeId::ThrowExpr:
                return true;

            case AstNodeId::IfStmt:
            {
                const auto& ifStmt = node.cast<AstIfStmt>();
                return ifStmt.nodeElseBlockRef.isValid() && nodeStopsLocalFlow(sema, ifStmt.nodeIfBlockRef) && nodeStopsLocalFlow(sema, ifStmt.nodeElseBlockRef);
            }

            case AstNodeId::IfVarDecl:
            {
                const auto& ifVarDecl = node.cast<AstIfVarDecl>();
                return ifVarDecl.nodeElseBlockRef.isValid() && nodeStopsLocalFlow(sema, ifVarDecl.nodeIfBlockRef) && nodeStopsLocalFlow(sema, ifVarDecl.nodeElseBlockRef);
            }

            case AstNodeId::EmbeddedBlock:
            case AstNodeId::FunctionBody:
            case AstNodeId::SwitchCaseBody:
            case AstNodeId::ElseStmt:
            case AstNodeId::ElseIfStmt:
            {
                SmallVector<AstNodeRef> children;
                node.collectChildrenFromAst(children, sema.ast());
                if (children.empty())
                    return false;
                return nodeStopsLocalFlow(sema, children.back());
            }

            default:
                return false;
        }
    }

    void maybePropagateIfStmtFallthroughNonNullGuard(Sema& sema, const AstIfStmt& node)
    {
        if (node.nodeElseBlockRef.isValid() || !nodeStopsLocalFlow(sema, node.nodeIfBlockRef))
            return;

        const auto* payload = sema.semaPayload<IfStmtNonNullGuardPayload>(sema.curNodeRef());
        if (!payload || !payload->elseSymbol)
            return;

        const AstNodeRef parentRef = sema.visit().parentNodeRef();
        if (parentRef.isInvalid())
            return;

        auto frame = sema.frame();
        frame.addNonNullSymbol(payload->elseSymbol);
        sema.pushFramePopOnPostNode(frame, parentRef);
    }

    TypeRef normalizeWithBindingType(TaskContext& ctx, TypeRef typeRef)
    {
        while (typeRef.isValid())
        {
            const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
            if (typeInfo.isAlias())
            {
                typeRef = typeInfo.payloadSymAlias().underlyingTypeRef();
                continue;
            }

            if (typeInfo.isReference() || typeInfo.isAnyPointer())
            {
                typeRef = typeInfo.payloadTypeRef();
                continue;
            }

            break;
        }

        return typeRef;
    }

    AstNodeRef withBindingExprRef(Sema& sema, AstNodeRef exprRef)
    {
        if (exprRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNode& node = sema.node(exprRef);
        if (node.is(AstNodeId::AssignStmt))
            return node.cast<AstAssignStmt>().nodeLeftRef;

        const AstNodeRef resolvedRef = sema.viewZero(exprRef).nodeRef();
        if (!resolvedRef.isValid())
            return exprRef;

        const AstNode& resolvedNode = sema.node(resolvedRef);
        if (resolvedNode.is(AstNodeId::AssignStmt))
            return resolvedNode.cast<AstAssignStmt>().nodeLeftRef;

        // When the `with` expression is an address-of (`&var`), unwrap to the underlying
        // variable so that configureWithBindings can use the direct variable binding path.
        // Without this, the address-of expression would be stored as a baseExprRef and
        // cloned during auto-member resolution, but the clone's children are never visited
        // by the codegen walker (they are not part of the original AST tree).
        if (resolvedNode.is(AstNodeId::UnaryExpr))
        {
            const Token& tok = sema.token(resolvedNode.codeRef());
            if (tok.id == TokenId::SymAmpersand)
                return resolvedNode.cast<AstUnaryExpr>().nodeExprRef;
        }

        return resolvedRef;
    }

    bool singleVariableSymbol(Sema& sema, AstNodeRef nodeRef, SymbolVariable*& outSym)
    {
        outSym = nullptr;

        const SemaNodeView view   = sema.view(nodeRef, SemaNodeViewPartE::Symbol);
        Symbol*            symbol = view.singleSymbol();
        if (!symbol || !symbol->isVariable())
            return false;

        outSym = &symbol->cast<SymbolVariable>();
        return true;
    }

    Result configureWithBindings(Sema& sema, AstNodeRef errorRef, Symbol* symbol, TypeRef rawTypeRef, AstNodeRef baseExprRef, SemaFrame& ioFrame, SemaScope& bodyScope)
    {
        if (symbol && symbol->isNamespace())
        {
            bodyScope.addUsingSymMap(symbol->asSymMap());
            bodyScope.addAutoMemberBinding({.symMap = symbol->asSymMap()});
            return Result::Continue;
        }

        if (symbol && symbol->isEnum())
        {
            bodyScope.addUsingSymMap(symbol->asSymMap());
            bodyScope.addAutoMemberBinding({.symMap = symbol->asSymMap()});
            return Result::Continue;
        }

        const TypeRef normalizedTypeRef = normalizeWithBindingType(sema.ctx(), rawTypeRef);
        if (!normalizedTypeRef.isValid())
        {
            if (rawTypeRef.isValid())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, errorRef);
                diag.addArgument(Diagnostic::ARG_TYPE, rawTypeRef);
                diag.report(sema.ctx());
                return Result::Error;
            }

            return SemaError::raise(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, errorRef);
        }

        const TypeInfo& typeInfo = sema.typeMgr().get(normalizedTypeRef);
        if (typeInfo.isStruct() || typeInfo.isAggregateStruct() || typeInfo.isEnum())
        {
            if (typeInfo.isEnum())
                bodyScope.addUsingSymMap(typeInfo.payloadSymEnum().asSymMap());

            SymbolVariable* symVar = symbol ? symbol->safeCast<SymbolVariable>() : nullptr;
            if (symVar &&
                (symVar->hasGlobalStorage() ||
                 symVar->hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
                 symVar->hasExtraFlag(SymbolVariableFlagsE::FunctionLocal) ||
                 symVar->hasExtraFlag(SymbolVariableFlagsE::RetVal) ||
                 symVar->isClosureCapture()))
            {
                ioFrame.pushBindingVar(symVar);
            }
            else
            {
                const SymbolMap* symMap = nullptr;
                if (typeInfo.isStruct())
                    symMap = &typeInfo.payloadSymStruct();
                else if (typeInfo.isEnum())
                    symMap = &typeInfo.payloadSymEnum();

                bodyScope.addAutoMemberBinding({.symMap = symMap, .typeRef = normalizedTypeRef, .baseExprRef = baseExprRef});
            }

            return Result::Continue;
        }

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, errorRef);
        diag.addArgument(Diagnostic::ARG_TYPE, normalizedTypeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result checkIfVarDeclCondition(Sema& sema, AstNodeRef varDeclRef)
    {
        AstNodeRef     declRef = varDeclRef;
        const AstNode& varNode = sema.node(varDeclRef);
        if (varNode.is(AstNodeId::VarDeclList))
        {
            const auto&             list = varNode.cast<AstVarDeclList>();
            SmallVector<AstNodeRef> decls;
            sema.ast().appendNodes(decls, list.spanChildrenRef);
            if (decls.size() != 1)
                return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, varDeclRef);
            declRef = decls.front();
        }

        const SemaNodeView declView = sema.view(declRef, SemaNodeViewPartE::Symbol);
        const Symbol*      sym      = declView.singleSymbol();
        if (!sym)
            return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, declRef);

        const TypeRef typeRef = sym->typeRef();
        if (typeRef.isInvalid())
            return Result::Continue;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isConvertibleToBoolAliasAware(sema.ctx()))
            return Result::Continue;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_cannot_cast, sym->codeRef());
        diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
        diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, sema.typeMgr().typeBool());
        diag.report(sema.ctx());
        return Result::Error;
    }
}

Result AstIfStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeIfBlockRef || childRef == nodeElseBlockRef)
    {
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);

        if (const Symbol* nonNullSymbol = ifStmtNonNullGuardSymbol(sema, sema.curNodeRef(), childRef, nodeIfBlockRef, nodeElseBlockRef))
        {
            auto scopedFrame = sema.frame();
            scopedFrame.addNonNullSymbol(nonNullSymbol);
            sema.pushFramePopOnPostChild(scopedFrame, childRef);
        }
    }

    return Result::Continue;
}

Result AstIfStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeConditionRef)
    {
        storeIfStmtNonNullGuard(sema, sema.curNodeRef(), nodeConditionRef);
        SemaNodeView view = sema.viewNodeTypeConstant(nodeConditionRef);
        SWC_RESULT(SemaCheck::castToBool(sema, view));
    }

    return Result::Continue;
}

Result AstIfStmt::semaPostNode(Sema& sema) const
{
    maybePropagateIfStmtFallthroughNonNullGuard(sema, *this);
    return Result::Continue;
}

Result AstIfVarDecl::semaPreNode(Sema& sema)
{
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    return Result::Continue;
}

Result AstIfVarDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeIfBlockRef || childRef == nodeElseBlockRef)
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);

    return Result::Continue;
}

Result AstIfVarDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeVarRef)
    {
        SWC_RESULT(checkIfVarDeclCondition(sema, nodeVarRef));
        const bool usesConditionBinding                                                                       = nodeWhereRef.isValid() && ifVarDeclNeedsWhereShortCircuit(sema, nodeVarRef);
        SemaHelpers::ensureCodeGenLoweringPayload(sema, sema.curNodeRef()).ifVarDeclWhereUsesConditionBinding = usesConditionBinding;
        if (usesConditionBinding)
        {
            maybeMaskIfVarDeclConditionForWhere(sema, sema.curNodeRef(), nodeVarRef);
        }
    }

    if (childRef == nodeWhereRef)
    {
        SemaNodeView view   = sema.viewNodeTypeConstant(nodeWhereRef);
        const Result result = SemaCheck::castToBool(sema, view);
        restoreMaskedIfVarDeclCondition(sema, sema.curNodeRef());
        return result;
    }

    return Result::Continue;
}

Result AstElseStmt::semaPreNode(Sema& sema)
{
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    return Result::Continue;
}

Result AstElseIfStmt::semaPreNode(Sema& sema)
{
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    return Result::Continue;
}

Result AstWithStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    const AstNodeRef   baseExprRef = withBindingExprRef(sema, nodeExprRef);
    const SemaNodeView exprView    = sema.viewNodeTypeSymbol(baseExprRef);

    auto       scopedFrame = sema.frame();
    SemaScope* bodyScope   = sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);
    SWC_RESULT(configureWithBindings(sema, nodeExprRef, exprView.sym(), exprView.typeRef(), baseExprRef, scopedFrame, *bodyScope));
    sema.pushFramePopOnPostChild(scopedFrame, childRef);
    return Result::Continue;
}

Result AstWithVarDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    SymbolVariable* symVar = nullptr;
    if (!singleVariableSymbol(sema, nodeVarRef, symVar))
        return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, nodeVarRef);

    auto       scopedFrame = sema.frame();
    SemaScope* bodyScope   = sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);
    SWC_RESULT(configureWithBindings(sema, nodeVarRef, symVar, symVar->typeRef(), AstNodeRef::invalid(), scopedFrame, *bodyScope));
    sema.pushFramePopOnPostChild(scopedFrame, childRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
