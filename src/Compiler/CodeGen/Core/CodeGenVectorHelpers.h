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

    // The packed variable-count shift of a shift operator on the given lanes.
    MicroOp variableShiftMicroOpForLane(TokenId tokId, const TypeInfo& laneType);

    // Emits an element-wise compare and returns the mask register (all-ones
    // lanes where the compare holds).
    MicroReg emitCompare(CodeGen& codeGen, TokenId tokId, MicroReg leftReg, MicroReg rightReg, const TypeInfo& laneType);
}

SWC_END_NAMESPACE();
