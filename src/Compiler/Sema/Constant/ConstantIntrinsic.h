#pragma once
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;
struct SemaNodeView;

namespace ConstantIntrinsic
{
    void   tryConstantFoldDataOf(Sema& sema, TypeRef resultTypeRef, const SemaNodeView& view);
    Result tryConstantFoldCall(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args);
}

SWC_END_NAMESPACE();
