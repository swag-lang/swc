#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;
struct SemaNodeView;

namespace ConstantIntrinsic
{
    void   tryConstantFoldDataOf(Sema& sema, TypeRef resultTypeRef, const SemaNodeView& view);
    Result tryConstantFoldCallBeforeParameterCasts(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args);
    Result tryConstantFoldCall(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args);
}

SWC_END_NAMESPACE();
