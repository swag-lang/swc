#include "pch.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isNamedArgument(const AstNode& node)
    {
        return node.is(AstNodeId::NamedArgument);
    }

    AstNodeRef inlineExprRef(const Sema& sema, const SymbolFunction& fn)
    {
        const auto* decl = fn.decl() ? fn.decl()->safeCast<AstFunctionDecl>() : nullptr;
        if (!decl)
            return AstNodeRef::invalid();

        if (decl->hasFlag(AstFunctionFlagsE::Short))
            return decl->nodeBodyRef;

        if (decl->nodeBodyRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNode& bodyNode = sema.node(decl->nodeBodyRef);
        const auto*    block    = bodyNode.safeCast<AstEmbeddedBlock>();
        if (!block)
            return AstNodeRef::invalid();

        SmallVector<AstNodeRef> statements;
        sema.ast().appendNodes(statements, block->spanChildrenRef);
        if (statements.size() != 1)
            return AstNodeRef::invalid();

        const auto* retStmt = sema.node(statements[0]).safeCast<AstReturnStmt>();
        if (!retStmt || retStmt->nodeExprRef.isInvalid())
            return AstNodeRef::invalid();

        return retStmt->nodeExprRef;
    }

    bool mapArguments(Sema& sema, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        const auto& params = fn.parameters();
        if (params.empty() && (ufcsArg.isValid() || !args.empty()))
            return false;

        std::vector bound(params.size(), AstNodeRef::invalid());
        size_t      nextParam = 0;

        if (ufcsArg.isValid())
        {
            if (params.empty())
                return false;
            bound[0]  = sema.getSubstituteRef(ufcsArg);
            nextParam = 1;
        }

        for (const auto argRef : args)
        {
            const AstNode& argNode = sema.node(argRef);
            if (!isNamedArgument(argNode))
                continue;

            const auto*         namedArg = argNode.cast<AstNamedArgument>();
            const IdentifierRef idRef    = sema.idMgr().addIdentifier(sema.ctx(), namedArg->codeRef());

            size_t paramIndex = params.size();
            for (size_t i = 0; i < params.size(); i++)
            {
                if (params[i]->idRef() == idRef)
                {
                    paramIndex = i;
                    break;
                }
            }

            if (paramIndex >= params.size())
                return false;
            if (bound[paramIndex].isValid())
                return false;

            bound[paramIndex] = sema.getSubstituteRef(namedArg->nodeArgRef);
        }

        for (const auto argRef : args)
        {
            const AstNode& argNode = sema.node(argRef);
            if (isNamedArgument(argNode))
                continue;

            while (nextParam < params.size() && bound[nextParam].isValid())
                nextParam++;
            if (nextParam >= params.size())
                return false;

            bound[nextParam++] = sema.getSubstituteRef(argRef);
        }

        if (bound.size() != params.size())
            return false;

        for (size_t i = 0; i < params.size(); i++)
        {
            if (!bound[i].isValid())
                return false;

            const SemaNodeView argView(sema, bound[i]);
            if (!argView.cstRef.isValid())
                return false;

            if (params[i]->idRef().isValid())
                outBindings.push_back({params[i]->idRef(), bound[i]});
        }

        return true;
    }

    bool hasVariadicParam(Sema& sema, const SymbolFunction& fn)
    {
        for (const auto* param : fn.parameters())
        {
            if (!param)
                continue;

            const TypeInfo& typeInfo = sema.typeMgr().get(param->typeRef());
            if (typeInfo.isAnyVariadic())
                return true;
        }

        return false;
    }
}

Result SemaInline::tryInlineCall(Sema& sema, AstNodeRef callRef, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
{
    if (!fn.isPure())
        return Result::Continue;
    if (fn.isClosure() || fn.isEmpty())
        return Result::Continue;
    if (hasVariadicParam(sema, fn))
        return Result::Continue;

    const AstNodeRef srcExprRef = inlineExprRef(sema, fn);
    if (srcExprRef.isInvalid())
        return Result::Continue;

    SmallVector<SemaClone::ParamBinding> bindings;
    if (!mapArguments(sema, fn, args, ufcsArg, bindings))
        return Result::Continue;

    const SemaClone::CloneContext cloneContext{bindings.span()};
    const AstNodeRef              inlinedRef = SemaClone::cloneExpr(sema, srcExprRef, cloneContext);
    SWC_ASSERT(inlinedRef.isValid());

    const TaskState saved = sema.ctx().state();
    Sema            inlineSema(sema.ctx(), sema, inlinedRef);
    if (fn.returnTypeRef() != sema.typeMgr().typeVoid())
        inlineSema.frame().pushBindingType(fn.returnTypeRef());
    RESULT_VERIFY(inlineSema.execResult());
    sema.ctx().state() = saved;

    if (fn.returnTypeRef() != sema.typeMgr().typeVoid())
    {
        SemaNodeView inlineView(sema, inlinedRef);
        RESULT_VERIFY(Cast::cast(sema, inlineView, fn.returnTypeRef(), CastKind::Implicit));
    }

    const SemaNodeView callView(sema, inlinedRef);
    SWC_ASSERT(callView.cstRef.isValid());
    sema.setConstant(callRef, callView.cstRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
