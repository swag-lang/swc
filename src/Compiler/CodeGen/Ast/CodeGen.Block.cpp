#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool needsSyntheticDeferScope(CodeGen& codeGen, AstNodeRef bodyRef)
    {
        bodyRef = codeGen.resolvedNodeRef(bodyRef);
        return bodyRef.isValid() && codeGen.node(bodyRef).isNot(AstNodeId::EmbeddedBlock);
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

Result AstDeferStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (codeGen.resolvedNodeRef(childRef) != codeGen.resolvedNodeRef(nodeBodyRef))
        return Result::Continue;

    SWC_RESULT(codeGen.registerDeferredBody(childRef));
    return Result::SkipChildren;
}

Result AstWithStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (codeGen.resolvedNodeRef(childRef) != codeGen.resolvedNodeRef(nodeBodyRef))
        return Result::Continue;

    if (needsSyntheticDeferScope(codeGen, childRef))
        codeGen.pushDeferScope(codeGen.resolvedNodeRef(childRef));

    return Result::Continue;
}

Result AstWithStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (codeGen.resolvedNodeRef(childRef) != codeGen.resolvedNodeRef(nodeBodyRef))
        return Result::Continue;

    if (needsSyntheticDeferScope(codeGen, childRef))
        SWC_RESULT(codeGen.popDeferScope());

    return Result::Continue;
}

Result AstWithVarDecl::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (codeGen.resolvedNodeRef(childRef) != codeGen.resolvedNodeRef(nodeBodyRef))
        return Result::Continue;

    if (needsSyntheticDeferScope(codeGen, childRef))
        codeGen.pushDeferScope(codeGen.resolvedNodeRef(childRef));

    return Result::Continue;
}

Result AstWithVarDecl::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (codeGen.resolvedNodeRef(childRef) != codeGen.resolvedNodeRef(nodeBodyRef))
        return Result::Continue;

    if (needsSyntheticDeferScope(codeGen, childRef))
        SWC_RESULT(codeGen.popDeferScope());

    return Result::Continue;
}

SWC_END_NAMESPACE();
