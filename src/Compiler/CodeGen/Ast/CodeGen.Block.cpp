#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // A mixin body is transparent: its defers belong to the caller's scope, not
    // an isolated scope of their own.  Returns true when the current node is
    // the inline root of a mixin expansion.
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
    // Parentheses are transparent at codegen time; only the wrapped expression carries the runtime payload.
    codeGen.inheritPayload(codeGen.curNodeRef(), nodeExprRef, codeGen.curViewType().typeRef());
    return Result::Continue;
}

Result AstNamedArgument::codeGenPostNode(CodeGen& codeGen) const
{
    // Named arguments only affect call matching earlier in the pipeline, not the lowered runtime value.
    codeGen.inheritPayload(codeGen.curNodeRef(), nodeArgRef, codeGen.curViewType().typeRef());
    return Result::Continue;
}

SWC_END_NAMESPACE();
