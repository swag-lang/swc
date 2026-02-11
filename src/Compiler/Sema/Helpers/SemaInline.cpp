#include "pch.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const SemaInline::ParamBinding* findBinding(const SemaInline::CloneContext& cloneContext, IdentifierRef idRef)
    {
        for (const auto& binding : cloneContext.bindings)
        {
            if (binding.idRef == idRef)
                return &binding;
        }

        return nullptr;
    }

    bool isNamedArgument(const AstNode& node)
    {
        return node.is(AstNodeId::NamedArgument);
    }

    AstNodeRef cloneExpr(Sema& sema, AstNodeRef nodeRef, const SemaInline::CloneContext& cloneContext);

    SpanRef cloneSpan(Sema& sema, SpanRef spanRef, const SemaInline::CloneContext& cloneContext)
    {
        if (spanRef.isInvalid())
            return SpanRef::invalid();

        SmallVector<AstNodeRef> children;
        sema.ast().appendNodes(children, spanRef);
        if (children.empty())
            return SpanRef::invalid();

        SmallVector<AstNodeRef> cloned;
        cloned.reserve(children.size());
        for (const auto childRef : children)
        {
            const AstNodeRef clonedRef = cloneExpr(sema, childRef, cloneContext);
            if (clonedRef.isInvalid())
                return SpanRef::invalid();
            cloned.push_back(clonedRef);
        }

        return sema.ast().pushSpan(cloned.span());
    }

    AstNodeRef cloneIdentifier(Sema& sema, const AstIdentifier& node, const SemaInline::CloneContext& cloneContext)
    {
        const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), node.codeRef());
        if (const auto* binding = findBinding(cloneContext, idRef))
            return binding->exprRef;

        auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::Identifier>(node.tokRef());
        nodePtr->flags()        = node.flags();
        return nodeRef;
    }

    AstNodeRef cloneExpr(Sema& sema, AstNodeRef nodeRef, const SemaInline::CloneContext& cloneContext)
    {
        if (nodeRef.isInvalid())
            return AstNodeRef::invalid();

        AstNode& node = sema.node(nodeRef);
        return Ast::nodeIdInfos(node.id()).semaInlineClone(sema, node, cloneContext);
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

    bool mapArguments(Sema& sema, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SmallVector<SemaInline::ParamBinding>& outBindings)
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

    bool shouldExposeConstantResult(const Sema& sema)
    {
        for (size_t up = 0;; up++)
        {
            const AstNode* parent = sema.visit().parentNode(up);
            if (!parent)
                return false;

            switch (parent->id())
            {
                case AstNodeId::CompilerExpression:
                case AstNodeId::CompilerDiagnostic:
                case AstNodeId::CompilerCall:
                case AstNodeId::CompilerCallOne:
                case AstNodeId::CompilerRunExpr:
                case AstNodeId::CompilerRunBlock:
                    return true;

                case AstNodeId::SingleVarDecl:
                    if (parent->cast<AstSingleVarDecl>()->hasFlag(AstVarDeclFlagsE::Const))
                        return true;
                    break;

                case AstNodeId::MultiVarDecl:
                    if (parent->cast<AstMultiVarDecl>()->hasFlag(AstVarDeclFlagsE::Const))
                        return true;
                    break;

                case AstNodeId::VarDeclDestructuring:
                    if (parent->cast<AstVarDeclDestructuring>()->hasFlag(AstVarDeclFlagsE::Const))
                        return true;
                    break;

                default:
                    break;
            }
        }
    }

    AstNodeRef makeRuntimeInlineResultNode(Sema& sema, AstNodeRef callRef, AstNodeRef inlinedRef, TypeRef returnTypeRef)
    {
        const AstNode& callNode = sema.node(callRef);
        auto [wrapRef, wrapPtr] = sema.ast().makeNode<AstNodeId::ImplicitCastExpr>(callNode.tokRef());
        wrapPtr->nodeExprRef    = inlinedRef;
        sema.setType(wrapRef, returnTypeRef);
        sema.setIsValue(*wrapPtr);
        return wrapRef;
    }
}

#define SWC_INLINE_CLONE_LITERAL(__type)                                                                     \
    AstNodeRef Ast##__type::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext&) const \
    {                                                                                                        \
        return sema.ast().makeNode<AstNodeId::__type>(tokRef()).first;                                       \
    }

SWC_INLINE_CLONE_LITERAL(BoolLiteral)
SWC_INLINE_CLONE_LITERAL(CharacterLiteral)
SWC_INLINE_CLONE_LITERAL(FloatLiteral)
SWC_INLINE_CLONE_LITERAL(IntegerLiteral)
SWC_INLINE_CLONE_LITERAL(BinaryLiteral)
SWC_INLINE_CLONE_LITERAL(HexaLiteral)
SWC_INLINE_CLONE_LITERAL(NullLiteral)
SWC_INLINE_CLONE_LITERAL(StringLiteral)
SWC_INLINE_CLONE_LITERAL(CompilerLiteral)
SWC_INLINE_CLONE_LITERAL(UndefinedExpr)
SWC_INLINE_CLONE_LITERAL(IntrinsicValue)

#undef SWC_INLINE_CLONE_LITERAL

#define SWC_INLINE_CLONE_UNARY(__type)                                                                                \
    AstNodeRef Ast##__type::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const \
    {                                                                                                                 \
        auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::__type>(tokRef());                                     \
        newPtr->nodeExprRef   = cloneExpr(sema, nodeExprRef, cloneContext);                                               \
        return newRef;                                                                                                \
    }

SWC_INLINE_CLONE_UNARY(ParenExpr)
SWC_INLINE_CLONE_UNARY(UnaryExpr)
SWC_INLINE_CLONE_UNARY(CountOfExpr)
SWC_INLINE_CLONE_UNARY(ImplicitCastExpr)
SWC_INLINE_CLONE_UNARY(DiscardExpr)
SWC_INLINE_CLONE_UNARY(TryCatchExpr)
SWC_INLINE_CLONE_UNARY(ThrowExpr)

#undef SWC_INLINE_CLONE_UNARY

AstNodeRef AstIdentifier::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    return cloneIdentifier(sema, *this, cloneContext);
}

AstNodeRef AstBinaryExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::BinaryExpr>(tokRef());
    newPtr->modifierFlags = modifierFlags;
    newPtr->nodeLeftRef   = cloneExpr(sema, nodeLeftRef, cloneContext);
    newPtr->nodeRightRef  = cloneExpr(sema, nodeRightRef, cloneContext);
    return newRef;
}

AstNodeRef AstLogicalExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::LogicalExpr>(tokRef());
    newPtr->nodeLeftRef   = cloneExpr(sema, nodeLeftRef, cloneContext);
    newPtr->nodeRightRef  = cloneExpr(sema, nodeRightRef, cloneContext);
    return newRef;
}

AstNodeRef AstRelationalExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::RelationalExpr>(tokRef());
    newPtr->nodeLeftRef   = cloneExpr(sema, nodeLeftRef, cloneContext);
    newPtr->nodeRightRef  = cloneExpr(sema, nodeRightRef, cloneContext);
    return newRef;
}

AstNodeRef AstNullCoalescingExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::NullCoalescingExpr>(tokRef());
    newPtr->nodeLeftRef   = cloneExpr(sema, nodeLeftRef, cloneContext);
    newPtr->nodeRightRef  = cloneExpr(sema, nodeRightRef, cloneContext);
    return newRef;
}

AstNodeRef AstConditionalExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::ConditionalExpr>(tokRef());
    newPtr->nodeCondRef   = cloneExpr(sema, nodeCondRef, cloneContext);
    newPtr->nodeTrueRef   = cloneExpr(sema, nodeTrueRef, cloneContext);
    newPtr->nodeFalseRef  = cloneExpr(sema, nodeFalseRef, cloneContext);
    return newRef;
}

AstNodeRef AstRangeExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::RangeExpr>(tokRef());
    newPtr->flags()         = flags();
    newPtr->nodeExprDownRef = cloneExpr(sema, nodeExprDownRef, cloneContext);
    newPtr->nodeExprUpRef   = cloneExpr(sema, nodeExprUpRef, cloneContext);
    return newRef;
}

AstNodeRef AstIndexExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::IndexExpr>(tokRef());
    newPtr->nodeExprRef   = cloneExpr(sema, nodeExprRef, cloneContext);
    newPtr->nodeArgRef    = cloneExpr(sema, nodeArgRef, cloneContext);
    return newRef;
}

AstNodeRef AstIndexListExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::IndexListExpr>(tokRef());
    newPtr->nodeExprRef     = cloneExpr(sema, nodeExprRef, cloneContext);
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContext);
    return newRef;
}

AstNodeRef AstStructInitializerList::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::StructInitializerList>(tokRef());
    newPtr->nodeWhatRef   = cloneExpr(sema, nodeWhatRef, cloneContext);
    newPtr->spanArgsRef   = cloneSpan(sema, spanArgsRef, cloneContext);
    return newRef;
}

AstNodeRef AstCallExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::CallExpr>(tokRef());
    newPtr->nodeExprRef     = cloneExpr(sema, nodeExprRef, cloneContext);
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContext);
    return newRef;
}

AstNodeRef AstIntrinsicCallExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::IntrinsicCallExpr>(tokRef());
    newPtr->nodeExprRef     = cloneExpr(sema, nodeExprRef, cloneContext);
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContext);
    return newRef;
}

AstNodeRef AstAliasCallExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::AliasCallExpr>(tokRef());
    newPtr->nodeExprRef     = cloneExpr(sema, nodeExprRef, cloneContext);
    newPtr->spanAliasesRef  = cloneSpan(sema, spanAliasesRef, cloneContext);
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContext);
    return newRef;
}

AstNodeRef AstNamedArgument::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::NamedArgument>(tokRef());
    newPtr->nodeArgRef    = cloneExpr(sema, nodeArgRef, cloneContext);
    return newRef;
}

AstNodeRef AstAutoMemberAccessExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::AutoMemberAccessExpr>(tokRef());
    newPtr->flags()       = flags();
    newPtr->nodeIdentRef  = cloneExpr(sema, nodeIdentRef, cloneContext);
    return newRef;
}

AstNodeRef AstMemberAccessExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::MemberAccessExpr>(tokRef());
    newPtr->flags()       = flags();
    newPtr->nodeLeftRef   = cloneExpr(sema, nodeLeftRef, cloneContext);
    newPtr->nodeRightRef  = cloneExpr(sema, nodeRightRef, cloneContext);
    return newRef;
}

AstNodeRef AstQuotedExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::QuotedExpr>(tokRef());
    newPtr->nodeExprRef   = cloneExpr(sema, nodeExprRef, cloneContext);
    newPtr->nodeSuffixRef = cloneExpr(sema, nodeSuffixRef, cloneContext);
    return newRef;
}

AstNodeRef AstQuotedListExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::QuotedListExpr>(tokRef());
    newPtr->nodeExprRef     = cloneExpr(sema, nodeExprRef, cloneContext);
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContext);
    return newRef;
}

AstNodeRef AstExplicitCastExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::ExplicitCastExpr>(tokRef());
    newPtr->modifierFlags = modifierFlags;
    newPtr->nodeTypeRef   = nodeTypeRef;
    newPtr->nodeExprRef   = cloneExpr(sema, nodeExprRef, cloneContext);
    return newRef;
}

AstNodeRef AstAutoCastExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::AutoCastExpr>(tokRef());
    newPtr->modifierFlags = modifierFlags;
    newPtr->nodeExprRef   = cloneExpr(sema, nodeExprRef, cloneContext);
    return newRef;
}

AstNodeRef AstAsCastExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::AsCastExpr>(tokRef());
    newPtr->nodeExprRef   = cloneExpr(sema, nodeExprRef, cloneContext);
    newPtr->nodeTypeRef   = nodeTypeRef;
    return newRef;
}

AstNodeRef AstIsTypeExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::IsTypeExpr>(tokRef());
    newPtr->nodeExprRef   = cloneExpr(sema, nodeExprRef, cloneContext);
    newPtr->nodeTypeRef   = nodeTypeRef;
    return newRef;
}

AstNodeRef AstInitializerExpr::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::InitializerExpr>(tokRef());
    newPtr->modifierFlags = modifierFlags;
    newPtr->nodeExprRef   = cloneExpr(sema, nodeExprRef, cloneContext);
    return newRef;
}

AstNodeRef AstArrayLiteral::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::ArrayLiteral>(tokRef());
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContext);
    return newRef;
}

AstNodeRef AstStructLiteral::semaInlineCloneExpr(Sema& sema, const SemaInline::CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::StructLiteral>(tokRef());
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContext);
    return newRef;
}

bool SemaInline::tryInlineCall(Sema& sema, AstNodeRef callRef, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
{
    if (!fn.isPure())
        return false;
    if (fn.isClosure() || fn.isEmpty())
        return false;
    if (hasVariadicParam(sema, fn))
        return false;

    const AstNodeRef srcExprRef = inlineExprRef(sema, fn);
    if (srcExprRef.isInvalid())
        return false;

    SmallVector<SemaInline::ParamBinding> bindings;
    if (!mapArguments(sema, fn, args, ufcsArg, bindings))
        return false;

    const SemaInline::CloneContext cloneContext{bindings.span()};
    const AstNodeRef               inlinedRef = cloneExpr(sema, srcExprRef, cloneContext);
    if (inlinedRef.isInvalid())
        return false;

    const TaskState saved = sema.ctx().state();
    Sema            inlineSema(sema.ctx(), sema, inlinedRef);
    inlineSema.exec();
    sema.ctx().state() = saved;

    AstNodeRef finalRef = inlinedRef;
    if (fn.returnTypeRef().isValid() && fn.returnTypeRef() != sema.typeMgr().typeVoid())
    {
        SemaNodeView inlineView(sema, inlinedRef);
        if (Cast::cast(sema, inlineView, fn.returnTypeRef(), CastKind::Implicit) == Result::Continue)
            finalRef = inlineView.nodeRef;
        else
            return false;
    }

    if (sema.hasConstant(finalRef) && shouldExposeConstantResult(sema))
        sema.setConstant(callRef, sema.constantRefOf(finalRef));
    else
        sema.setSubstitute(callRef, makeRuntimeInlineResultNode(sema, callRef, finalRef, fn.returnTypeRef()));

    return true;
}

SWC_END_NAMESPACE();
