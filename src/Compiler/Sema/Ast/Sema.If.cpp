#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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

        return resolvedRef;
    }

    bool singleVariableSymbol(Sema& sema, AstNodeRef nodeRef, SymbolVariable*& outSym)
    {
        outSym = nullptr;

        SmallVector<Symbol*> symbols;
        const SemaNodeView   view = sema.view(nodeRef, SemaNodeViewPartE::Symbol);
        if (view.hasSymbolList())
        {
            const std::span<Symbol*> symList = view.symList();
            symbols.reserve(symList.size());
            for (Symbol* sym : symList)
                symbols.push_back(sym);
        }
        else if (view.hasSymbol())
        {
            symbols.push_back(view.sym());
        }

        if (symbols.size() != 1 || !symbols.front()->isVariable())
            return false;

        outSym = &symbols.front()->cast<SymbolVariable>();
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
            return SemaError::raise(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, errorRef);

        const TypeInfo& typeInfo = sema.typeMgr().get(normalizedTypeRef);
        if (typeInfo.isStruct() || typeInfo.isAggregateStruct() || typeInfo.isEnum())
        {
            if (typeInfo.isEnum())
                bodyScope.addUsingSymMap(typeInfo.payloadSymEnum().asSymMap());

            if (SymbolVariable* symVar = symbol ? symbol->safeCast<SymbolVariable>() : nullptr;
                symVar &&
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

        return SemaError::raise(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, errorRef);
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

        SmallVector<Symbol*> symbols;
        const SemaNodeView   declView = sema.view(declRef, SemaNodeViewPartE::Symbol);
        if (declView.hasSymbolList())
        {
            const std::span<Symbol*> list = declView.symList();
            symbols.reserve(list.size());
            for (Symbol* sym : list)
                symbols.push_back(sym);
        }
        else if (declView.hasSymbol())
        {
            symbols.push_back(declView.sym());
        }

        if (symbols.size() != 1)
            return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, declRef);

        const Symbol* sym     = symbols.front();
        const TypeRef typeRef = sym->typeRef();
        if (typeRef.isInvalid())
            return Result::Continue;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isConvertibleToBool())
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
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);

    return Result::Continue;
}

Result AstIfStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeConditionRef)
    {
        SemaNodeView view = sema.viewNodeTypeConstant(nodeConditionRef);
        SWC_RESULT(Cast::cast(sema, view, sema.typeMgr().typeBool(), CastKind::Condition));
    }

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
        SWC_RESULT(checkIfVarDeclCondition(sema, nodeVarRef));

    if (childRef == nodeWhereRef)
    {
        SemaNodeView view = sema.viewNodeTypeConstant(nodeWhereRef);
        SWC_RESULT(Cast::cast(sema, view, sema.typeMgr().typeBool(), CastKind::Condition));
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
