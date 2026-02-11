#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;
struct SemaNodeView;

namespace ConstantIntrinsic
{
    bool   isPureIntrinsic(Sema& sema, const SymbolFunction& selectedFn);
    Result tryConstantFoldCall(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args);
    Result tryConstantFoldCall(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args, std::span<const ConstantRef> argCsts, AstNodeRef callRef, ConstantRef& outResult);
};

SWC_END_NAMESPACE();
