#pragma once
#include <cstdint>

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;

enum class SpecOpKind : uint8_t
{
    None,
    Invalid,
    OpBinary,
    OpUnary,
    OpAssign,
    OpIndexAssign,
    OpCast,
    OpEquals,
    OpCmp,
    OpPostCopy,
    OpPostMove,
    OpDrop,
    OpCount,
    OpData,
    OpAffect,
    OpAffectLiteral,
    OpSlice,
    OpIndex,
    OpIndexAffect,
    OpVisit,
};

namespace SemaSpecOp
{
    SpecOpKind computeSymbolKind(const Sema& sema, const SymbolFunction& sym);
    Result     validateSymbol(Sema& sema, SymbolFunction& sym);
    Result     registerSymbol(Sema& sema, SymbolFunction& sym);
}

SWC_END_NAMESPACE();
