#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Helpers/SemaInline.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // A mixin body shares the caller's scope, so its defers must stay there.
    bool isMixinBody(CodeGen& codeGen)
    {
        const SemaInlinePayload* inlinePayload = codeGen.sema().inlinePayload(codeGen.curNodeRef());
        return inlinePayload &&
               inlinePayload->inlineRootRef == codeGen.curNodeRef() &&
               inlinePayload->sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::Mixin);
    }
}

Result AstEmbeddedBlock::codeGenPreNode(CodeGen& codeGen)
{
    codeGen.pushDeferScope(codeGen.curNodeRef());
    return Result::Continue;
}

Result AstEmbeddedBlock::codeGenPostNode(CodeGen& codeGen)
{
    return codeGen.popDeferScope();
}

Result AstFunctionBody::codeGenPreNode(CodeGen& codeGen)
{
    if (isMixinBody(codeGen))
        return Result::Continue;

    codeGen.pushDeferScope(codeGen.curNodeRef());
    return Result::Continue;
}

Result AstFunctionBody::codeGenPostNode(CodeGen& codeGen)
{
    if (isMixinBody(codeGen))
        return Result::Continue;

    return codeGen.popDeferScope();
}

Result AstDeferStmt::codeGenPreNode(CodeGen& codeGen)
{
    const auto& node = codeGen.curNode().cast<AstDeferStmt>();
    codeGen.registerDefer(codeGen.curNodeRef(), node.nodeBodyRef, node.modifierFlags);
    return Result::SkipChildren;
}

Result AstParenExpr::codeGenPostNode(CodeGen& codeGen) const
{
    codeGen.inheritPayload(codeGen.curNodeRef(), nodeExprRef, codeGen.transparentPayloadTypeRef());
    return Result::Continue;
}

Result AstNamedArgument::codeGenPostNode(CodeGen& codeGen) const
{
    codeGen.inheritPayload(codeGen.curNodeRef(), nodeArgRef, codeGen.transparentPayloadTypeRef());
    return Result::Continue;
}

SWC_END_NAMESPACE();
