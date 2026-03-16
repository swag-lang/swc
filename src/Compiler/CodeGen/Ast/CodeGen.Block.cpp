#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"

SWC_BEGIN_NAMESPACE();

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
