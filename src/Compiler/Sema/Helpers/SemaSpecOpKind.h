#pragma once

SWC_BEGIN_NAMESPACE();

enum class SpecOpKind : uint8_t
{
    None,
    Invalid,
    OpBinary,
    OpBinaryRight,
    OpUnary,
    OpAssign,
    OpIndexAssign,
    OpCast,
    OpEquals,
    OpCompare,
    OpPostCopy,
    OpPostMove,
    OpDrop,
    OpCount,
    OpData,
    OpSet,
    OpSetLiteral,
    OpSlice,
    OpIndex,
    OpIndexSet,
    OpIndexPtr,
    OpVisit,
};

SWC_END_NAMESPACE();
