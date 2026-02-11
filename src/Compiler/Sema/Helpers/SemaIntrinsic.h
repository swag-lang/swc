#pragma once
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;
struct SemaNodeView;
struct AstCallExpr;

namespace SemaIntrinsic
{
    Result tryConstantFoldCall(Sema& sema, const AstCallExpr& call, const SymbolFunction& selectedFn, std::span<AstNodeRef> args);
};

SWC_END_NAMESPACE();
