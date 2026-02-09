#pragma once
#include "Compiler/Sema/Symbol/Symbol.h"
#include <cstdint>

SWC_BEGIN_NAMESPACE();

enum class SpecOpKind : uint8_t
{
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

SWC_END_NAMESPACE();
