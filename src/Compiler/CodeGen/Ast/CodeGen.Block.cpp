#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"

SWC_BEGIN_NAMESPACE();

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
    codeGen.pushDeferScope(codeGen.curNodeRef());
    return Result::Continue;
}

Result AstFunctionBody::codeGenPostNode(CodeGen& codeGen)
{
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
