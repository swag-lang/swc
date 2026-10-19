#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroTypes.h"
#include "Compiler/Lexer/Token.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class TypeInfo;
struct CodeGenNodePayload;

// Shared SIMD lowering for B128 values in floating-point registers:
// operand loads, constants, broadcasts, masks and per-lane operations.
namespace CodeGenVectorHelpers
{
    enum class LaneReduceKind
    {
        Add,
        Min,
        Max,
        And,
        Or,
        Xor,
    };

    // Load address-backed vectors into a float register; reuse value registers.
    MicroReg loadVectorOperand(CodeGen& codeGen, const CodeGenNodePayload& payload);

    // Broadcast a lane-typed scalar into every lane of a new vector register.
    MicroReg splatScalarLane(CodeGen& codeGen, MicroReg scalarReg, const TypeInfo& laneType);

    // Load a 16-byte constant through the constant segment.
    MicroReg loadVectorConstant(CodeGen& codeGen, TypeRef typeRef, std::span<const std::byte> bytes);

    // An all-ones vector, built without a constant from any live register.
    MicroReg allOnes(CodeGen& codeGen, MicroReg anyVecReg);

    // dst = ~src, through an all-ones xor.
    MicroReg bitwiseNot(CodeGen& codeGen, MicroReg srcReg);

    // Select a packed arithmetic or bitwise operation; shifts use separate helpers.
    MicroOp binaryMicroOpForLane(TokenId tokId, const TypeInfo& laneType);

    // Emits the low wrapping product for 8- or 64-bit integer lanes, whose
    // packed forms require decomposition on the baseline target.
    MicroReg emitDecomposedMultiply(CodeGen& codeGen, MicroReg leftReg, MicroReg rightReg, const TypeInfo& laneType);

    // Shifts every lane by one scalar count. Shapes without a direct packed
    // instruction are synthesized without leaving the register file.
    MicroReg emitVariableShift(CodeGen& codeGen, TokenId tokId, MicroReg valueReg, MicroReg countVecReg, const TypeInfo& laneType);

    // Use an immediate shift for constant counts below the lane width when supported.
    // Otherwise return an invalid register so the caller can use emitVariableShift.
    MicroReg emitConstantShift(CodeGen& codeGen, TokenId tokId, MicroReg valueReg, const TypeInfo& laneType, AstNodeRef countOperandRef);

    // Shift by an immediate count. Byte lanes use word shifts and masks
    // to remove bits that crossed lane boundaries.
    MicroReg emitLaneShiftImm(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType, uint32_t count, bool shiftLeft);

    // Rotate every lane, reducing immediate or register counts modulo the lane
    // width to match Swag.rol and Swag.ror.
    MicroReg emitRotateImm(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType, uint32_t count, bool rotateLeft);
    MicroReg emitRotateVar(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType, MicroReg countReg, bool rotateLeft);

    // Count set bits per lane using a nibble table and a reduction to lane width.
    MicroReg emitPopCount(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType);

    // Count leading or trailing zero bits per lane; zero lanes yield the lane width.
    MicroReg emitCountTrailingZeros(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType);
    MicroReg emitCountLeadingZeros(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType);

    // Reverses the bytes of every lane, as one dynamic byte permute.
    MicroReg emitByteSwap(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType);

    // Clears the sign bit of every float lane.
    MicroReg emitFloatAbs(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType);

    // The element-wise minimum or maximum of two vectors, including the 64-bit
    // integer lanes the baseline has no instruction for.
    MicroReg emitMinMax(CodeGen& codeGen, MicroReg leftReg, MicroReg rightReg, const TypeInfo& laneType, bool wantMin);

    // Combines every lane into one, leaving the answer in lane zero.
    MicroReg emitLaneReduction(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType, LaneReduceKind kind);

    // Reads lane zero into a scalar register of the lane type.
    MicroReg emitExtractLaneZero(CodeGen& codeGen, MicroReg vectorReg, const TypeInfo& laneType);

    // Sums the absolute byte differences of each half into the low word of the
    // matching 64-bit lane; signed bytes bias into the unsigned instruction.
    MicroReg emitSumAbsoluteDifferences(CodeGen& codeGen, MicroReg leftReg, MicroReg rightReg, const TypeInfo& laneType);

    // Permutes lanes through a pattern known here: a 32-bit lane permutation
    // selects the immediate form, anything else a constant byte table.
    MicroReg emitConstantShuffle(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType, std::span<const uint8_t> laneIndices);

    // Permutes lanes through a pattern that only exists at run time.
    MicroReg emitDynamicShuffle(CodeGen& codeGen, MicroReg valueReg, MicroReg patternReg, const TypeInfo& laneType);

    // The same over two vectors, an index past the lane count reading the second.
    MicroReg emitConstantShuffle2(CodeGen& codeGen, MicroReg firstReg, MicroReg secondReg, const TypeInfo& laneType, std::span<const uint8_t> laneIndices);
    MicroReg emitDynamicShuffle2(CodeGen& codeGen, MicroReg firstReg, MicroReg secondReg, MicroReg patternReg, const TypeInfo& laneType, const TypeInfo& byteLaneType);

    // Return the high half of each full lane product, interpreting operands
    // with the lane type's signedness.
    MicroReg emitMultiplyHigh(CodeGen& codeGen, MicroReg leftReg, MicroReg rightReg, const TypeInfo& laneType);

    // Sixteen bytes of the concatenation of two vectors, starting at a byte
    // offset; the bytes past the concatenation are zero.
    MicroReg emitConstantAlign(CodeGen& codeGen, MicroReg lowReg, MicroReg highReg, uint32_t count);
    MicroReg emitDynamicAlign(CodeGen& codeGen, MicroReg lowReg, MicroReg highReg, MicroReg countReg, const TypeInfo& byteLaneType);

    // Return a comparison mask with all bits set in matching lanes.
    MicroReg emitCompare(CodeGen& codeGen, TokenId tokId, MicroReg leftReg, MicroReg rightReg, const TypeInfo& laneType);
}

SWC_END_NAMESPACE();
