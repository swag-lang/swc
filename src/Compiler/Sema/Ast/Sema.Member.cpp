#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result substituteNativeProjection(Sema& sema, const AstMemberAccessExpr& node)
    {
        const TokenRef tokNameRef = sema.node(node.nodeRightRef).tokRef();
        AstNodeRef     substituteRef;
        if (node.projectionId == TokenId::IntrinsicCountOf)
        {
            auto [newRef, substitute] = sema.ast().makeNode<AstNodeId::CountOfExpr>(tokNameRef);
            substitute->nodeExprRef   = node.nodeLeftRef;
            substituteRef             = newRef;
        }
        else
        {
            SWC_ASSERT(node.projectionId == TokenId::IntrinsicDataOf);
            SmallVector<AstNodeRef> children;
            children.push_back(node.nodeLeftRef);
            auto [newRef, substitute]   = sema.ast().makeNode<AstNodeId::IntrinsicCall>(tokNameRef);
            substitute->intrinsicId     = TokenId::IntrinsicDataOf;
            substitute->spanChildrenRef = sema.ast().pushSpan(children.span());
            substituteRef               = newRef;
        }

        sema.setSubstitute(sema.curNodeRef(), substituteRef);
        sema.restartCurrentNode(substituteRef);
        return Result::Continue;
    }
}

Result AstMemberAccessExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    if (childRef == nodeLeftRef && projectionId != TokenId::Invalid)
        return substituteNativeProjection(sema, *this);

    if (childRef != nodeRightRef)
        return Result::Continue;

    bool allowOverloadSet = hasFlag(AstMemberAccessExprFlagsE::CallCallee);
    if (const auto* ident = sema.node(nodeRightRef).safeCast<AstIdentifier>())
        allowOverloadSet = allowOverloadSet || ident->hasFlag(AstIdentifierFlagsE::InCompilerDefined);
    return SemaHelpers::resolveMemberAccess(sema, sema.curNodeRef(), *this, allowOverloadSet);
}

Result AstMemberAccessExpr::semaPostNode(Sema& sema) const
{
    if (projectionId == TokenId::Invalid)
        return Result::Continue;
    return substituteNativeProjection(sema, *this);
}

SWC_END_NAMESPACE();
