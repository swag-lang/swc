#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class SymbolFunction;
class TypeInfo;
struct CodeGenNodePayload;

namespace CodeGenSafety
{
    Result emitBoundCheck(CodeGen& codeGen, AstNodeRef indexRef, const TypeInfo& indexedType, const CodeGenNodePayload& indexedPayload, MicroReg indexReg);
    Result emitSwitchCheck(CodeGen& codeGen, const AstNode& node, SymbolFunction* panicFunction);
    Result emitUnreachableCheck(CodeGen& codeGen, const AstNode& node);
}

SWC_END_NAMESPACE();
