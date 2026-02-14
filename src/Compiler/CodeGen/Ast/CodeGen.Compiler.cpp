#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

Result AstCompilerRunExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView exprView(codeGen.sema(), nodeExprRef);
    if (exprView.cst && exprView.type && !exprView.type->isStruct())
        RESULT_VERIFY(codeGen.emitConstReturnValue(exprView));

    codeGen.builder().encodeRet(EncodeFlagsE::Zero);
    return Result::Continue;
}

SWC_END_NAMESPACE();
