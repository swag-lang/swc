#pragma once
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;
struct ResolvedCallArgument;

namespace SemaJIT
{
    Result runStatement(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeRef);
    Result runExpr(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeExprRef);
    Result tryRunConstCall(Sema& sema, SymbolFunction& calledFn, AstNodeRef callRef, std::span<const ResolvedCallArgument> resolvedArgs);
    Result tryRunConstAffectCall(Sema&                                 sema,
                                 SymbolFunction&                       calledFn,
                                 AstNodeRef                            callRef,
                                 std::span<const ResolvedCallArgument> resolvedArgs,
                                 TypeRef                               receiverTypeRef,
                                 ConstantRef                           receiverInitCstRef,
                                 bool                                  forceEvaluation = false);
}

SWC_END_NAMESPACE();
