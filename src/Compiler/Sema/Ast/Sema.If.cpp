#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result checkIfVarDeclCondition(Sema& sema, AstNodeRef varDeclRef)
    {
        AstNodeRef  declRef = varDeclRef;
        const auto& varNode = sema.node(varDeclRef);
        if (varNode.is(AstNodeId::VarDeclList))
        {
            const AstVarDeclList*   list = varNode.cast<AstVarDeclList>();
            SmallVector<AstNodeRef> decls;
            sema.ast().appendNodes(decls, list->spanChildrenRef);
            if (decls.size() != 1)
                return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, varDeclRef);
            declRef = decls.front();
        }

        SmallVector<Symbol*> symbols;
        if (sema.hasSymbolList(declRef))
        {
            const auto list = sema.getSymbolList(declRef);
            symbols.reserve(list.size());
            for (Symbol* sym : list)
                symbols.push_back(sym);
        }
        else if (sema.hasSymbol(declRef))
        {
            symbols.push_back(&sema.symbolOf(declRef));
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
        SemaNodeView nodeView = sema.nodeView(nodeConditionRef);
        RESULT_VERIFY(Cast::cast(sema, nodeView, sema.typeMgr().typeBool(), CastKind::Condition));
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
        RESULT_VERIFY(checkIfVarDeclCondition(sema, nodeVarRef));

    if (childRef == nodeWhereRef)
    {
        SemaNodeView nodeView = sema.nodeView(nodeWhereRef);
        RESULT_VERIFY(Cast::cast(sema, nodeView, sema.typeMgr().typeBool(), CastKind::Condition));
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

SWC_END_NAMESPACE();
