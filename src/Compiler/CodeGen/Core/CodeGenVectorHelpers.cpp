#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenVectorHelpers.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint32_t laneBitsOf(const TypeInfo& laneType)
    {
        return laneType.isFloat() ? laneType.payloadFloatBits() : laneType.payloadIntBits();
    }
}

MicroReg CodeGenVectorHelpers::loadVectorOperand(CodeGen& codeGen, const CodeGenNodePayload& payload)
{
    if (!payload.isAddress())
        return payload.reg;

    const MicroReg resultReg = codeGen.nextVirtualFloatRegister();
    codeGen.builder().emitLoadVecRegMem(resultReg, payload.reg, 0, MicroOpBits::B128);
    return resultReg;
}

MicroReg CodeGenVectorHelpers::splatScalarLane(CodeGen& codeGen, MicroReg scalarReg, const TypeInfo& laneType)
{
    MicroBuilder&  builder  = codeGen.builder();
    const uint32_t laneBits = laneBitsOf(laneType);
    const MicroReg dstReg   = codeGen.nextVirtualFloatRegister();

    // Floats already sit in lane zero of a float register: one four-lane
    // permute broadcasts them.
    if (laneType.isFloat())
    {
        builder.emitVecShuffleRegRegImm(dstReg, scalarReg, laneBits == 32 ? 0x00 : 0x44, MicroOpBits::B128);
        return dstReg;
    }

    // Narrow integers are repeated into one 32-bit scalar before movd. Keeping
    // the replication in the integer register file avoids depending on a chain
    // of self-interleaves whose first result can be coalesced away.
    MicroReg packedScalarReg = scalarReg;
    if (laneBits == 8 || laneBits == 16)
    {
        packedScalarReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(packedScalarReg, scalarReg, MicroOpBits::B32);
        const uint64_t laneMask   = laneBits == 8 ? 0xFF : 0xFFFF;
        const uint64_t multiplier = laneBits == 8 ? 0x01010101 : 0x00010001;
        builder.emitOpBinaryRegImm(packedScalarReg, ApInt(laneMask, 64), MicroOp::And, MicroOpBits::B32);
        builder.emitOpBinaryRegImm(packedScalarReg, ApInt(multiplier, 64), MicroOp::MultiplySigned, MicroOpBits::B32);
    }

    const MicroReg seedReg = codeGen.nextVirtualFloatRegister();
    builder.emitLoadRegReg(seedReg, packedScalarReg, laneBits == 64 ? MicroOpBits::B64 : MicroOpBits::B32);

    if (laneBits == 64)
    {
        builder.emitVecShuffleRegRegImm(dstReg, seedReg, 0x44, MicroOpBits::B128);
        return dstReg;
    }

    builder.emitVecShuffleRegRegImm(dstReg, seedReg, 0x00, MicroOpBits::B128);
    return dstReg;
}

MicroReg CodeGenVectorHelpers::loadVectorConstant(CodeGen& codeGen, TypeRef typeRef, std::span<const std::byte> bytes)
{
    SWC_ASSERT(bytes.size() == 16);
    const ConstantRef cstRef = CodeGenConstantHelpers::materializeStaticPayloadConstant(codeGen, typeRef, bytes);
    SWC_ASSERT(cstRef.isValid());

    MicroBuilder&        builder = codeGen.builder();
    const ConstantValue& cst     = codeGen.cstMgr().get(cstRef);
    const MicroReg       addrReg = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegPtrReloc(addrReg, reinterpret_cast<uint64_t>(cst.getArray().data()), cstRef);

    const MicroReg resultReg = codeGen.nextVirtualFloatRegister();
    builder.emitLoadVecRegMem(resultReg, addrReg, 0, MicroOpBits::B128);
    return resultReg;
}

MicroReg CodeGenVectorHelpers::allOnes(CodeGen& codeGen, MicroReg anyVecReg)
{
    // A bitwise self-equality holds in every lane whatever the register
    // carries, NaN payloads included.
    const MicroReg resultReg = codeGen.nextVirtualFloatRegister();
    codeGen.builder().emitOpBinaryRegRegReg(resultReg, anyVecReg, anyVecReg, MicroOp::VecCmpEq32, MicroOpBits::B128);
    return resultReg;
}

MicroReg CodeGenVectorHelpers::bitwiseNot(CodeGen& codeGen, MicroReg srcReg)
{
    const MicroReg onesReg   = allOnes(codeGen, srcReg);
    const MicroReg resultReg = codeGen.nextVirtualFloatRegister();
    codeGen.builder().emitOpBinaryRegRegReg(resultReg, srcReg, onesReg, MicroOp::VecXor, MicroOpBits::B128);
    return resultReg;
}

MicroOp CodeGenVectorHelpers::binaryMicroOpForLane(TokenId tokId, const TypeInfo& laneType)
{
    const uint32_t laneBits = laneBitsOf(laneType);
    if (laneType.isFloat())
    {
        switch (tokId)
        {
            case TokenId::SymPlus:
                return laneBits == 32 ? MicroOp::VecAddF32 : MicroOp::VecAddF64;
            case TokenId::SymMinus:
                return laneBits == 32 ? MicroOp::VecSubF32 : MicroOp::VecSubF64;
            case TokenId::SymAsterisk:
                return laneBits == 32 ? MicroOp::VecMulF32 : MicroOp::VecMulF64;
            case TokenId::SymSlash:
                return laneBits == 32 ? MicroOp::VecDivF32 : MicroOp::VecDivF64;
            default:
                SWC_UNREACHABLE();
        }
    }

    switch (tokId)
    {
        case TokenId::SymPlus:
            switch (laneBits)
            {
                case 8: return MicroOp::VecAdd8;
                case 16: return MicroOp::VecAdd16;
                case 32: return MicroOp::VecAdd32;
                default: return MicroOp::VecAdd64;
            }
        case TokenId::SymMinus:
            switch (laneBits)
            {
                case 8: return MicroOp::VecSub8;
                case 16: return MicroOp::VecSub16;
                case 32: return MicroOp::VecSub32;
                default: return MicroOp::VecSub64;
            }
        case TokenId::SymAsterisk:
            return laneBits == 16 ? MicroOp::VecMul16 : MicroOp::VecMul32;
        case TokenId::SymAmpersand:
            return MicroOp::VecAnd;
        case TokenId::SymPipe:
            return MicroOp::VecOr;
        case TokenId::SymCircumflex:
            return MicroOp::VecXor;
        default:
            SWC_UNREACHABLE();
    }
}

MicroOp CodeGenVectorHelpers::variableShiftMicroOpForLane(TokenId tokId, const TypeInfo& laneType)
{
    const uint32_t laneBits = laneBitsOf(laneType);
    if (tokId == TokenId::SymLowerLower)
    {
        switch (laneBits)
        {
            case 16: return MicroOp::VecShiftLeftV16;
            case 32: return MicroOp::VecShiftLeftV32;
            default: return MicroOp::VecShiftLeftV64;
        }
    }

    SWC_ASSERT(tokId == TokenId::SymGreaterGreater);
    if (laneType.isIntSigned())
        return laneBits == 16 ? MicroOp::VecShiftRightAV16 : MicroOp::VecShiftRightAV32;

    switch (laneBits)
    {
        case 16: return MicroOp::VecShiftRightV16;
        case 32: return MicroOp::VecShiftRightV32;
        default: return MicroOp::VecShiftRightV64;
    }
}

MicroReg CodeGenVectorHelpers::emitCompare(CodeGen& codeGen, TokenId tokId, MicroReg leftReg, MicroReg rightReg, const TypeInfo& laneType)
{
    MicroBuilder&  builder  = codeGen.builder();
    const uint32_t laneBits = laneBitsOf(laneType);

    if (laneType.isFloat())
    {
        const MicroOp cmpOp = laneBits == 32 ? MicroOp::VecCmpF32 : MicroOp::VecCmpF64;

        // The hardware predicates cover EQ/LT/LE/NEQ; the greater forms swap
        // their operands.
        uint8_t  predicate = 0;
        MicroReg lhs       = leftReg;
        MicroReg rhs       = rightReg;
        switch (tokId)
        {
            case TokenId::SymEqualEqual:
                predicate = 0;
                break;
            case TokenId::SymBangEqual:
                predicate = 4;
                break;
            case TokenId::SymLess:
                predicate = 1;
                break;
            case TokenId::SymLessEqual:
                predicate = 2;
                break;
            case TokenId::SymGreater:
                predicate = 1;
                std::swap(lhs, rhs);
                break;
            case TokenId::SymGreaterEqual:
                predicate = 2;
                std::swap(lhs, rhs);
                break;
            default:
                SWC_UNREACHABLE();
        }

        const MicroReg resultReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpTernaryRegRegRegImm(resultReg, lhs, rhs, predicate, cmpOp, MicroOpBits::B128);
        return resultReg;
    }

    MicroOp eqOp = MicroOp::VecCmpEq32;
    MicroOp gtOp = MicroOp::VecCmpGtS32;
    switch (laneBits)
    {
        case 8:
            eqOp = MicroOp::VecCmpEq8;
            gtOp = MicroOp::VecCmpGtS8;
            break;
        case 16:
            eqOp = MicroOp::VecCmpEq16;
            gtOp = MicroOp::VecCmpGtS16;
            break;
        case 32:
            break;
        default:
            eqOp = MicroOp::VecCmpEq64;
            gtOp = MicroOp::VecCmpGtS64;
            break;
    }

    if (tokId == TokenId::SymEqualEqual || tokId == TokenId::SymBangEqual)
    {
        const MicroReg eqReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegReg(eqReg, leftReg, rightReg, eqOp, MicroOpBits::B128);
        return tokId == TokenId::SymEqualEqual ? eqReg : bitwiseNot(codeGen, eqReg);
    }

    // Unsigned lanes have no greater-than: bias both sides by the lane sign
    // bit and compare signed.
    MicroReg lhs = leftReg;
    MicroReg rhs = rightReg;
    if (laneType.isIntUnsigned())
    {
        std::array<std::byte, 16> bias{};
        const uint32_t            laneBytes = laneBits / 8;
        for (uint32_t byteIndex = 0; byteIndex < 16; ++byteIndex)
            bias[byteIndex] = (byteIndex % laneBytes == laneBytes - 1) ? std::byte{0x80} : std::byte{0};

        const TypeRef  biasTypeRef = codeGen.typeMgr().addType(TypeInfo::makeSimd(laneType.typeRef(), 16 / laneBytes));
        const MicroReg biasReg     = loadVectorConstant(codeGen, biasTypeRef, {bias.data(), bias.size()});
        const MicroReg biasedLhs   = codeGen.nextVirtualFloatRegister();
        const MicroReg biasedRhs   = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegReg(biasedLhs, leftReg, biasReg, MicroOp::VecXor, MicroOpBits::B128);
        builder.emitOpBinaryRegRegReg(biasedRhs, rightReg, biasReg, MicroOp::VecXor, MicroOpBits::B128);
        lhs = biasedLhs;
        rhs = biasedRhs;
    }

    // gt(l, r) answers '>' directly and '<' swapped; the or-equal forms
    // complement the swapped strict compare.
    const MicroReg resultReg = codeGen.nextVirtualFloatRegister();
    switch (tokId)
    {
        case TokenId::SymGreater:
            builder.emitOpBinaryRegRegReg(resultReg, lhs, rhs, gtOp, MicroOpBits::B128);
            return resultReg;
        case TokenId::SymLess:
            builder.emitOpBinaryRegRegReg(resultReg, rhs, lhs, gtOp, MicroOpBits::B128);
            return resultReg;
        case TokenId::SymGreaterEqual:
            builder.emitOpBinaryRegRegReg(resultReg, rhs, lhs, gtOp, MicroOpBits::B128);
            return bitwiseNot(codeGen, resultReg);
        case TokenId::SymLessEqual:
            builder.emitOpBinaryRegRegReg(resultReg, lhs, rhs, gtOp, MicroOpBits::B128);
            return bitwiseNot(codeGen, resultReg);
        default:
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();
