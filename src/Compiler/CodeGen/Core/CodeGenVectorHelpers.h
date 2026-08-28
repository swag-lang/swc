#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroTypes.h"
#include "Compiler/Lexer/Token.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class TypeInfo;
struct CodeGenNodePayload;

// Shared lowering for the '#simd' vector type: operand loads, scalar
// broadcasts, 16-byte constants, mask building, and the per-lane operation
// tables. Every routine works on B128 values living in the float register
// file.
namespace CodeGenVectorHelpers
{
    // Loads a vector operand into a float register: an address-backed payload
    // loads its 16 bytes, a value payload is used in place.
    MicroReg loadVectorOperand(CodeGen& codeGen, const CodeGenNodePayload& payload);

    // Broadcasts a lane-typed scalar register into every lane of a new vector
    // register.
    MicroReg splatScalarLane(CodeGen& codeGen, MicroReg scalarReg, const TypeInfo& laneType);

    // Materializes a 16-byte constant into a vector register through the
    // constant segment.
    MicroReg loadVectorConstant(CodeGen& codeGen, TypeRef typeRef, std::span<const std::byte> bytes);

    // An all-ones vector, built without a constant from any live register.
    MicroReg allOnes(CodeGen& codeGen, MicroReg anyVecReg);

    // dst = ~src, through an all-ones xor.
    MicroReg bitwiseNot(CodeGen& codeGen, MicroReg srcReg);

    // The packed operation of an element-wise arithmetic or bitwise operator
    // on the given lanes. Shifts are handled separately.
    MicroOp binaryMicroOpForLane(TokenId tokId, const TypeInfo& laneType);

    // Emits the low wrapping product for 8- or 64-bit integer lanes, whose
    // packed forms require decomposition on the baseline target.
    MicroReg emitDecomposedMultiply(CodeGen& codeGen, MicroReg leftReg, MicroReg rightReg, const TypeInfo& laneType);

    // Shifts every lane by one scalar count. Shapes without a direct packed
    // instruction are synthesized without leaving the register file.
    MicroReg emitVariableShift(CodeGen& codeGen, TokenId tokId, MicroReg valueReg, MicroReg countVecReg, const TypeInfo& laneType);

    // Shifts every lane by a count known here. Byte lanes borrow the word shift
    // and mask the bits that crossed their boundary, which is what the hardware
    // leaves out.
    MicroReg emitLaneShiftImm(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType, uint32_t count, bool shiftLeft);

    // Rotates every lane, by a count known here or carried in an integer
    // register. Both reduce the count modulo the lane width, like the scalar
    // '@rol' and '@ror'.
    MicroReg emitRotateImm(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType, uint32_t count, bool rotateLeft);
    MicroReg emitRotateVar(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType, MicroReg countReg, bool rotateLeft);

    // Per-lane population count, through the nibble table every popcount
    // lowering uses, then a reduction to the lane width.
    MicroReg emitPopCount(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType);

    // Per-lane zero counts below the lowest and above the highest set bit. An
    // all-zero lane answers the lane width, like the scalar intrinsics.
    MicroReg emitCountTrailingZeros(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType);
    MicroReg emitCountLeadingZeros(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType);

    // Reverses the bytes of every lane, as one dynamic byte permute.
    MicroReg emitByteSwap(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType);

    // Clears the sign bit of every float lane.
    MicroReg emitFloatAbs(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType);

    // Emits an element-wise compare and returns the mask register (all-ones
    // lanes where the compare holds).
    MicroReg emitCompare(CodeGen& codeGen, TokenId tokId, MicroReg leftReg, MicroReg rightReg, const TypeInfo& laneType);
}

SWC_END_NAMESPACE();
