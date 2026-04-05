#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class TypeInfo;
struct CodeGenNodePayload;

namespace CodeGenSafety
{
    Result emitBoundCheck(CodeGen& codeGen, AstNodeRef indexRef, const TypeInfo& indexedType, const CodeGenNodePayload& indexedPayload, MicroReg indexReg);
}

SWC_END_NAMESPACE();
