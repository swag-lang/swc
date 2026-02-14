#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"

SWC_BEGIN_NAMESPACE();

Result AstCompilerRunExpr::codeGenPostNode(CodeGen& codeGen) const
{
    codeGen.builder()->encodeRet(EncodeFlagsE::Zero);
    return Result::Continue;
}

SWC_END_NAMESPACE();
