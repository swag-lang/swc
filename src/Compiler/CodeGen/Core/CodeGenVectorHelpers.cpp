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

MicroReg CodeGenVectorHelpers::emitDecomposedMultiply(CodeGen& codeGen, MicroReg leftReg, MicroReg rightReg, const TypeInfo& laneType)
{
    MicroBuilder&  builder  = codeGen.builder();
    const uint32_t laneBits = laneBitsOf(laneType);
    SWC_ASSERT(!laneType.isFloat() && (laneBits == 8 || laneBits == 64));

    if (laneBits == 8)
    {
        // Unsigned widening is sufficient even for signed lanes: only the low
        // eight product bits survive, so both interpretations are identical.
        const MicroReg leftHighBytesReg  = codeGen.nextVirtualFloatRegister();
        const MicroReg rightHighBytesReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegImm(leftHighBytesReg, leftReg, ApInt(8, 8), MicroOp::VecShiftRightBytes, MicroOpBits::B128);
        builder.emitOpBinaryRegRegImm(rightHighBytesReg, rightReg, ApInt(8, 8), MicroOp::VecShiftRightBytes, MicroOpBits::B128);

        const MicroReg leftLowWideReg   = codeGen.nextVirtualFloatRegister();
        const MicroReg leftHighWideReg  = codeGen.nextVirtualFloatRegister();
        const MicroReg rightLowWideReg  = codeGen.nextVirtualFloatRegister();
        const MicroReg rightHighWideReg = codeGen.nextVirtualFloatRegister();
        builder.emitVecUnaryRegReg(leftLowWideReg, leftReg, MicroOp::VecWidenLoU8, MicroOpBits::B128);
        builder.emitVecUnaryRegReg(leftHighWideReg, leftHighBytesReg, MicroOp::VecWidenLoU8, MicroOpBits::B128);
        builder.emitVecUnaryRegReg(rightLowWideReg, rightReg, MicroOp::VecWidenLoU8, MicroOpBits::B128);
        builder.emitVecUnaryRegReg(rightHighWideReg, rightHighBytesReg, MicroOp::VecWidenLoU8, MicroOpBits::B128);

        const MicroReg lowProductReg  = codeGen.nextVirtualFloatRegister();
        const MicroReg highProductReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegReg(lowProductReg, leftLowWideReg, rightLowWideReg, MicroOp::VecMul16, MicroOpBits::B128);
        builder.emitOpBinaryRegRegReg(highProductReg, leftHighWideReg, rightHighWideReg, MicroOp::VecMul16, MicroOpBits::B128);

        const MicroReg onesReg     = allOnes(codeGen, leftReg);
        const MicroReg byteMaskReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegImm(byteMaskReg, onesReg, ApInt(8, 8), MicroOp::VecShiftRight16, MicroOpBits::B128);
        const MicroReg maskedLowReg  = codeGen.nextVirtualFloatRegister();
        const MicroReg maskedHighReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegReg(maskedLowReg, lowProductReg, byteMaskReg, MicroOp::VecAnd, MicroOpBits::B128);
        builder.emitOpBinaryRegRegReg(maskedHighReg, highProductReg, byteMaskReg, MicroOp::VecAnd, MicroOpBits::B128);

        const MicroReg resultReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegReg(resultReg, maskedLowReg, maskedHighReg, MicroOp::VecPackUS16, MicroOpBits::B128);
        return resultReg;
    }

    // For each qword, keep low*low and the low 32 bits of both cross
    // products. The omitted high*high term starts above bit 63.
    const MicroReg leftHighReg  = codeGen.nextVirtualFloatRegister();
    const MicroReg rightHighReg = codeGen.nextVirtualFloatRegister();
    builder.emitOpBinaryRegRegImm(leftHighReg, leftReg, ApInt(32, 8), MicroOp::VecShiftRight64, MicroOpBits::B128);
    builder.emitOpBinaryRegRegImm(rightHighReg, rightReg, ApInt(32, 8), MicroOp::VecShiftRight64, MicroOpBits::B128);

    const MicroReg lowProductReg = codeGen.nextVirtualFloatRegister();
    const MicroReg cross1Reg     = codeGen.nextVirtualFloatRegister();
    const MicroReg cross2Reg     = codeGen.nextVirtualFloatRegister();
    builder.emitOpBinaryRegRegReg(lowProductReg, leftReg, rightReg, MicroOp::VecMulU32Wide, MicroOpBits::B128);
    builder.emitOpBinaryRegRegReg(cross1Reg, leftHighReg, rightReg, MicroOp::VecMulU32Wide, MicroOpBits::B128);
    builder.emitOpBinaryRegRegReg(cross2Reg, leftReg, rightHighReg, MicroOp::VecMulU32Wide, MicroOpBits::B128);

    const MicroReg crossSumReg = codeGen.nextVirtualFloatRegister();
    builder.emitOpBinaryRegRegReg(crossSumReg, cross1Reg, cross2Reg, MicroOp::VecAdd64, MicroOpBits::B128);
    const MicroReg shiftedCrossReg = codeGen.nextVirtualFloatRegister();
    builder.emitOpBinaryRegRegImm(shiftedCrossReg, crossSumReg, ApInt(32, 8), MicroOp::VecShiftLeft64, MicroOpBits::B128);

    const MicroReg resultReg = codeGen.nextVirtualFloatRegister();
    builder.emitOpBinaryRegRegReg(resultReg, lowProductReg, shiftedCrossReg, MicroOp::VecAdd64, MicroOpBits::B128);
    return resultReg;
}

MicroReg CodeGenVectorHelpers::emitVariableShift(CodeGen& codeGen, TokenId tokId, MicroReg valueReg, MicroReg countVecReg, const TypeInfo& laneType)
{
    MicroBuilder&  builder   = codeGen.builder();
    const uint32_t laneBits  = laneBitsOf(laneType);
    const bool     shiftLeft = tokId == TokenId::SymLowerLower;
    SWC_ASSERT(shiftLeft || tokId == TokenId::SymGreaterGreater);

    if (laneBits == 8)
    {
        // Widen each byte half to words, shift there, then narrow the halves
        // back together. Left shifts mask to eight bits before the saturating
        // pack so they preserve wrapping shift semantics.
        const bool    arithmeticRight = !shiftLeft && laneType.isIntSigned();
        const MicroOp widenOp         = arithmeticRight ? MicroOp::VecWidenLoS8 : MicroOp::VecWidenLoU8;
        const MicroOp shiftOp         = shiftLeft ? MicroOp::VecShiftLeftV16 : arithmeticRight ? MicroOp::VecShiftRightAV16
                                                                                               : MicroOp::VecShiftRightV16;

        const MicroReg highBytesReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegImm(highBytesReg, valueReg, ApInt(8, 8), MicroOp::VecShiftRightBytes, MicroOpBits::B128);

        const MicroReg lowWideReg  = codeGen.nextVirtualFloatRegister();
        const MicroReg highWideReg = codeGen.nextVirtualFloatRegister();
        builder.emitVecUnaryRegReg(lowWideReg, valueReg, widenOp, MicroOpBits::B128);
        builder.emitVecUnaryRegReg(highWideReg, highBytesReg, widenOp, MicroOpBits::B128);

        MicroReg lowShiftReg  = codeGen.nextVirtualFloatRegister();
        MicroReg highShiftReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegReg(lowShiftReg, lowWideReg, countVecReg, shiftOp, MicroOpBits::B128);
        builder.emitOpBinaryRegRegReg(highShiftReg, highWideReg, countVecReg, shiftOp, MicroOpBits::B128);

        if (shiftLeft)
        {
            const MicroReg onesReg     = allOnes(codeGen, valueReg);
            const MicroReg byteMaskReg = codeGen.nextVirtualFloatRegister();
            builder.emitOpBinaryRegRegImm(byteMaskReg, onesReg, ApInt(8, 8), MicroOp::VecShiftRight16, MicroOpBits::B128);

            const MicroReg maskedLowReg  = codeGen.nextVirtualFloatRegister();
            const MicroReg maskedHighReg = codeGen.nextVirtualFloatRegister();
            builder.emitOpBinaryRegRegReg(maskedLowReg, lowShiftReg, byteMaskReg, MicroOp::VecAnd, MicroOpBits::B128);
            builder.emitOpBinaryRegRegReg(maskedHighReg, highShiftReg, byteMaskReg, MicroOp::VecAnd, MicroOpBits::B128);
            lowShiftReg  = maskedLowReg;
            highShiftReg = maskedHighReg;
        }

        const MicroReg resultReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegReg(resultReg, lowShiftReg, highShiftReg, arithmeticRight ? MicroOp::VecPackSS16 : MicroOp::VecPackUS16, MicroOpBits::B128);
        return resultReg;
    }

    if (!shiftLeft && laneBits == 64 && laneType.isIntSigned())
    {
        // Arithmetic right shift is a logical shift plus the high sign fill.
        // Shifting an all-ones vector also makes counts >= 64 naturally select
        // a complete sign fill, as required by the language.
        const MicroReg logicalReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegReg(logicalReg, valueReg, countVecReg, MicroOp::VecShiftRightV64, MicroOpBits::B128);

        const MicroReg zeroReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegReg(zeroReg, valueReg, valueReg, MicroOp::VecXor, MicroOpBits::B128);
        const MicroReg signReg = emitCompare(codeGen, TokenId::SymGreater, zeroReg, valueReg, laneType);

        const MicroReg onesReg      = allOnes(codeGen, valueReg);
        const MicroReg preservedReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegReg(preservedReg, onesReg, countVecReg, MicroOp::VecShiftRightV64, MicroOpBits::B128);
        const MicroReg fillReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegReg(fillReg, preservedReg, signReg, MicroOp::VecAndNot, MicroOpBits::B128);

        const MicroReg resultReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegReg(resultReg, logicalReg, fillReg, MicroOp::VecOr, MicroOpBits::B128);
        return resultReg;
    }

    MicroOp op;
    if (tokId == TokenId::SymLowerLower)
    {
        switch (laneBits)
        {
            case 16: op = MicroOp::VecShiftLeftV16; break;
            case 32: op = MicroOp::VecShiftLeftV32; break;
            default: op = MicroOp::VecShiftLeftV64; break;
        }
    }
    else if (laneType.isIntSigned())
        op = laneBits == 16 ? MicroOp::VecShiftRightAV16 : MicroOp::VecShiftRightAV32;
    else
    {
        switch (laneBits)
        {
            case 16: op = MicroOp::VecShiftRightV16; break;
            case 32: op = MicroOp::VecShiftRightV32; break;
            default: op = MicroOp::VecShiftRightV64; break;
        }
    }

    const MicroReg resultReg = codeGen.nextVirtualFloatRegister();
    builder.emitOpBinaryRegRegReg(resultReg, valueReg, countVecReg, op, MicroOpBits::B128);
    return resultReg;
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

namespace
{
    // A 16-byte constant repeating one little-endian pattern every
    // 'patternBytes'. The lane masks and the small tables below all have this
    // shape, and the constant segment holds one copy per distinct pattern.
    MicroReg repeatedConstant(CodeGen& codeGen, uint32_t patternBytes, uint64_t pattern)
    {
        SWC_ASSERT(patternBytes == 1 || patternBytes == 2 || patternBytes == 4 || patternBytes == 8);

        std::array<std::byte, 16> bytes{};
        for (uint32_t index = 0; index < 16; ++index)
            bytes[index] = static_cast<std::byte>((pattern >> (8 * (index % patternBytes))) & 0xFF);

        const TypeManager& typeMgr     = codeGen.typeMgr();
        TypeRef            laneTypeRef = typeMgr.typeU8();
        if (patternBytes == 2)
            laneTypeRef = typeMgr.typeU16();
        else if (patternBytes == 4)
            laneTypeRef = typeMgr.typeU32();
        else if (patternBytes == 8)
            laneTypeRef = typeMgr.typeU64();

        const TypeRef vecTypeRef = codeGen.typeMgr().addType(TypeInfo::makeSimd(laneTypeRef, 16 / patternBytes));
        return CodeGenVectorHelpers::loadVectorConstant(codeGen, vecTypeRef, {bytes.data(), bytes.size()});
    }

    // A 16-byte constant naming one source byte per result byte, for the
    // dynamic byte permute.
    MicroReg byteTableConstant(CodeGen& codeGen, const std::array<uint8_t, 16>& tableBytes)
    {
        std::array<std::byte, 16> bytes{};
        for (uint32_t index = 0; index < 16; ++index)
            bytes[index] = static_cast<std::byte>(tableBytes[index]);

        const TypeRef vecTypeRef = codeGen.typeMgr().addType(TypeInfo::makeSimd(codeGen.typeMgr().typeU8(), 16));
        return CodeGenVectorHelpers::loadVectorConstant(codeGen, vecTypeRef, {bytes.data(), bytes.size()});
    }

    MicroReg emitVecBinary(CodeGen& codeGen, MicroReg leftReg, MicroReg rightReg, MicroOp op)
    {
        const MicroReg resultReg = codeGen.nextVirtualFloatRegister();
        codeGen.builder().emitOpBinaryRegRegReg(resultReg, leftReg, rightReg, op, MicroOpBits::B128);
        return resultReg;
    }

    MicroReg emitVecBinaryImm(CodeGen& codeGen, MicroReg srcReg, uint32_t immediate, MicroOp op)
    {
        const MicroReg resultReg = codeGen.nextVirtualFloatRegister();
        codeGen.builder().emitOpBinaryRegRegImm(resultReg, srcReg, ApInt(immediate, 8), op, MicroOpBits::B128);
        return resultReg;
    }

    // Population count of every byte, the nibble-table sequence every packed
    // popcount is built on.
    MicroReg emitBytePopCount(CodeGen& codeGen, MicroReg valueReg)
    {
        constexpr std::array<uint8_t, 16> NibbleCounts = {0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4};

        const MicroReg tableReg   = byteTableConstant(codeGen, NibbleCounts);
        const MicroReg lowMaskReg = repeatedConstant(codeGen, 1, 0x0F);

        // The word shift drags four bits of the neighbouring byte in; the low
        // nibble mask is exactly what drops them again.
        const MicroReg lowReg     = emitVecBinary(codeGen, valueReg, lowMaskReg, MicroOp::VecAnd);
        const MicroReg shiftedReg = emitVecBinaryImm(codeGen, valueReg, 4, MicroOp::VecShiftRight16);
        const MicroReg highReg    = emitVecBinary(codeGen, shiftedReg, lowMaskReg, MicroOp::VecAnd);

        const MicroReg lowCountReg  = emitVecBinary(codeGen, tableReg, lowReg, MicroOp::VecPermB);
        const MicroReg highCountReg = emitVecBinary(codeGen, tableReg, highReg, MicroOp::VecPermB);
        return emitVecBinary(codeGen, lowCountReg, highCountReg, MicroOp::VecAdd8);
    }
}

MicroReg CodeGenVectorHelpers::emitLaneShiftImm(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType, uint32_t count, bool shiftLeft)
{
    const uint32_t laneBits = laneBitsOf(laneType);
    SWC_ASSERT(count < laneBits);
    if (!count)
        return valueReg;

    // Byte lanes have no packed shift: they shift as words, and the mask drops
    // the bits that crossed into the neighbouring byte.
    const uint32_t shiftBits = laneBits == 8 ? 16 : laneBits;

    MicroOp op;
    switch (shiftBits)
    {
        case 16:
            op = shiftLeft ? MicroOp::VecShiftLeft16 : MicroOp::VecShiftRight16;
            break;
        case 32:
            op = shiftLeft ? MicroOp::VecShiftLeft32 : MicroOp::VecShiftRight32;
            break;
        default:
            op = shiftLeft ? MicroOp::VecShiftLeft64 : MicroOp::VecShiftRight64;
            break;
    }

    const MicroReg shiftedReg = emitVecBinaryImm(codeGen, valueReg, count, op);
    if (laneBits != 8)
        return shiftedReg;

    const uint64_t keep = shiftLeft ? (0xFFull << count) & 0xFFull : 0xFFull >> count;
    return emitVecBinary(codeGen, shiftedReg, repeatedConstant(codeGen, 1, keep), MicroOp::VecAnd);
}

MicroReg CodeGenVectorHelpers::emitRotateImm(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType, uint32_t count, bool rotateLeft)
{
    const uint32_t laneBits  = laneBitsOf(laneType);
    const uint32_t reduced   = count % laneBits;
    const uint32_t leftCount = rotateLeft ? reduced : (laneBits - reduced) % laneBits;
    if (!leftCount)
    {
        // A rotation by zero still owns a register of its own: the caller
        // publishes it as the result of the expression.
        const MicroReg copyReg = codeGen.nextVirtualFloatRegister();
        codeGen.builder().emitLoadRegReg(copyReg, valueReg, MicroOpBits::B128);
        return copyReg;
    }

    const MicroReg leftReg  = emitLaneShiftImm(codeGen, valueReg, laneType, leftCount, true);
    const MicroReg rightReg = emitLaneShiftImm(codeGen, valueReg, laneType, laneBits - leftCount, false);
    return emitVecBinary(codeGen, leftReg, rightReg, MicroOp::VecOr);
}

MicroReg CodeGenVectorHelpers::emitRotateVar(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType, MicroReg countReg, bool rotateLeft)
{
    MicroBuilder&  builder  = codeGen.builder();
    const uint32_t laneBits = laneBitsOf(laneType);

    // Reducing both counts modulo the lane width is what lets a zero count
    // return the value: the complementary shift would otherwise empty the lane.
    const MicroReg forwardReg = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegReg(forwardReg, countReg, MicroOpBits::B32);
    builder.emitOpBinaryRegImm(forwardReg, ApInt(laneBits - 1, 32), MicroOp::And, MicroOpBits::B32);

    const MicroReg backwardReg = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegImm(backwardReg, ApInt(laneBits, 32), MicroOpBits::B32);
    builder.emitOpBinaryRegReg(backwardReg, forwardReg, MicroOp::Subtract, MicroOpBits::B32);
    builder.emitOpBinaryRegImm(backwardReg, ApInt(laneBits - 1, 32), MicroOp::And, MicroOpBits::B32);

    const MicroReg forwardVecReg  = codeGen.nextVirtualFloatRegister();
    const MicroReg backwardVecReg = codeGen.nextVirtualFloatRegister();
    builder.emitLoadRegReg(forwardVecReg, forwardReg, MicroOpBits::B32);
    builder.emitLoadRegReg(backwardVecReg, backwardReg, MicroOpBits::B32);

    const MicroReg leftCountReg  = rotateLeft ? forwardVecReg : backwardVecReg;
    const MicroReg rightCountReg = rotateLeft ? backwardVecReg : forwardVecReg;
    const MicroReg leftPartReg   = emitVariableShift(codeGen, TokenId::SymLowerLower, valueReg, leftCountReg, laneType);
    const MicroReg rightPartReg  = emitVariableShift(codeGen, TokenId::SymGreaterGreater, valueReg, rightCountReg, laneType);
    return emitVecBinary(codeGen, leftPartReg, rightPartReg, MicroOp::VecOr);
}

MicroReg CodeGenVectorHelpers::emitPopCount(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType)
{
    const uint32_t laneBits = laneBitsOf(laneType);
    const MicroReg bytesReg = emitBytePopCount(codeGen, valueReg);
    if (laneBits == 8)
        return bytesReg;

    // Eight bytes of counts never exceed 64, so the sum of absolute
    // differences against zero is the whole qword reduction.
    if (laneBits == 64)
    {
        const MicroReg zeroReg = emitVecBinary(codeGen, valueReg, valueReg, MicroOp::VecXor);
        return emitVecBinary(codeGen, bytesReg, zeroReg, MicroOp::VecSadU8);
    }

    const MicroReg lowBytesReg  = emitVecBinary(codeGen, bytesReg, repeatedConstant(codeGen, 2, 0x00FF), MicroOp::VecAnd);
    const MicroReg highBytesReg = emitVecBinaryImm(codeGen, bytesReg, 8, MicroOp::VecShiftRight16);
    const MicroReg wordsReg     = emitVecBinary(codeGen, lowBytesReg, highBytesReg, MicroOp::VecAdd16);
    if (laneBits == 16)
        return wordsReg;

    const MicroReg lowWordsReg  = emitVecBinary(codeGen, wordsReg, repeatedConstant(codeGen, 4, 0x0000FFFF), MicroOp::VecAnd);
    const MicroReg highWordsReg = emitVecBinaryImm(codeGen, wordsReg, 16, MicroOp::VecShiftRight32);
    return emitVecBinary(codeGen, lowWordsReg, highWordsReg, MicroOp::VecAdd32);
}

MicroReg CodeGenVectorHelpers::emitCountTrailingZeros(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType)
{
    const uint32_t laneBits = laneBitsOf(laneType);
    const MicroOp  subOp    = laneBits == 8 ? MicroOp::VecSub8 : laneBits == 16 ? MicroOp::VecSub16
                                                             : laneBits == 32   ? MicroOp::VecSub32
                                                                                : MicroOp::VecSub64;

    // popcount((x & -x) - 1) counts the zeros below the lowest set bit, and an
    // empty lane borrows to all-ones, which is the lane width the language
    // asks for.
    const MicroReg zeroReg    = emitVecBinary(codeGen, valueReg, valueReg, MicroOp::VecXor);
    const MicroReg negatedReg = emitVecBinary(codeGen, zeroReg, valueReg, subOp);
    const MicroReg lowestReg  = emitVecBinary(codeGen, valueReg, negatedReg, MicroOp::VecAnd);
    const MicroReg belowReg   = emitVecBinary(codeGen, lowestReg, repeatedConstant(codeGen, laneBits / 8, 1), subOp);
    return emitPopCount(codeGen, belowReg, laneType);
}

MicroReg CodeGenVectorHelpers::emitCountLeadingZeros(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType)
{
    const uint32_t laneBits = laneBitsOf(laneType);

    // Smearing the highest set bit down turns the count into a population
    // count, and an empty lane smears to zero, whose complement is the width.
    MicroReg smearedReg = valueReg;
    for (uint32_t distance = 1; distance < laneBits; distance *= 2)
    {
        const MicroReg shiftedReg = emitLaneShiftImm(codeGen, smearedReg, laneType, distance, false);
        smearedReg                = emitVecBinary(codeGen, smearedReg, shiftedReg, MicroOp::VecOr);
    }

    return emitPopCount(codeGen, bitwiseNot(codeGen, smearedReg), laneType);
}

MicroReg CodeGenVectorHelpers::emitByteSwap(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType)
{
    const uint32_t laneBytes = laneBitsOf(laneType) / 8;
    SWC_ASSERT(laneBytes == 2 || laneBytes == 4 || laneBytes == 8);

    std::array<uint8_t, 16> indices{};
    for (uint32_t index = 0; index < 16; ++index)
    {
        const uint32_t lane = index / laneBytes;
        indices[index]      = static_cast<uint8_t>(lane * laneBytes + (laneBytes - 1 - index % laneBytes));
    }

    return emitVecBinary(codeGen, valueReg, byteTableConstant(codeGen, indices), MicroOp::VecPermB);
}

MicroReg CodeGenVectorHelpers::emitFloatAbs(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType)
{
    const uint32_t laneBits = laneBitsOf(laneType);
    SWC_ASSERT(laneBits == 32 || laneBits == 64);

    // Clearing the sign bit leaves everything else alone, so a NaN keeps its
    // payload and a negative zero becomes a positive one.
    const uint64_t magnitude = laneBits == 32 ? 0x7FFFFFFFull : 0x7FFFFFFFFFFFFFFFull;
    return emitVecBinary(codeGen, valueReg, repeatedConstant(codeGen, laneBits / 8, magnitude), MicroOp::VecAnd);
}

MicroReg CodeGenVectorHelpers::emitMinMax(CodeGen& codeGen, MicroReg leftReg, MicroReg rightReg, const TypeInfo& laneType, bool wantMin)
{
    MicroBuilder&  builder  = codeGen.builder();
    const uint32_t laneBits = laneBitsOf(laneType);
    const bool     isSigned = laneType.isIntSigned();

    if (!laneType.isFloat() && laneBits == 64)
    {
        // There is no packed 64-bit integer minimum or maximum before AVX-512:
        // the signed compare mask and a byte blend build it. The blend keeps
        // its destination where the mask is clear, so the losing side is copied
        // in first.
        const TokenId  cmpTokId = wantMin ? TokenId::SymLess : TokenId::SymGreater;
        const MicroReg maskReg  = emitCompare(codeGen, cmpTokId, leftReg, rightReg, laneType);
        const MicroReg dstReg   = codeGen.nextVirtualFloatRegister();
        builder.emitLoadRegReg(dstReg, rightReg, MicroOpBits::B128);
        builder.emitOpTernaryRegRegReg(dstReg, leftReg, maskReg, MicroOp::VecBlendVB, MicroOpBits::B128);
        return dstReg;
    }

    MicroOp op;
    if (laneType.isFloat())
        op = wantMin ? (laneBits == 32 ? MicroOp::VecMinF32 : MicroOp::VecMinF64) : (laneBits == 32 ? MicroOp::VecMaxF32 : MicroOp::VecMaxF64);
    else if (laneBits == 8)
        op = wantMin ? (isSigned ? MicroOp::VecMinS8 : MicroOp::VecMinU8) : (isSigned ? MicroOp::VecMaxS8 : MicroOp::VecMaxU8);
    else if (laneBits == 16)
        op = wantMin ? (isSigned ? MicroOp::VecMinS16 : MicroOp::VecMinU16) : (isSigned ? MicroOp::VecMaxS16 : MicroOp::VecMaxU16);
    else
        op = wantMin ? (isSigned ? MicroOp::VecMinS32 : MicroOp::VecMinU32) : (isSigned ? MicroOp::VecMaxS32 : MicroOp::VecMaxU32);

    const MicroReg dstReg = codeGen.nextVirtualFloatRegister();
    builder.emitOpBinaryRegRegReg(dstReg, leftReg, rightReg, op, MicroOpBits::B128);
    return dstReg;
}

MicroReg CodeGenVectorHelpers::emitLaneReduction(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType, LaneReduceKind kind)
{
    MicroBuilder&  builder   = codeGen.builder();
    const uint32_t laneBytes = laneBitsOf(laneType) / 8;

    // Fold the vector in half at every step: the byte shift brings the upper
    // half down over the lower one, and a single element-wise operation
    // combines them, so the whole reduction stays in the register file and the
    // combining order is a balanced tree over the lane index.
    MicroReg accReg = valueReg;
    for (uint32_t distance = 8; distance >= laneBytes; distance /= 2)
    {
        const MicroReg upperReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegImm(upperReg, accReg, ApInt(distance, 8), MicroOp::VecShiftRightBytes, MicroOpBits::B128);

        if (kind == LaneReduceKind::Min || kind == LaneReduceKind::Max)
        {
            accReg = emitMinMax(codeGen, accReg, upperReg, laneType, kind == LaneReduceKind::Min);
            continue;
        }

        TokenId opTokId = TokenId::SymPlus;
        if (kind == LaneReduceKind::And)
            opTokId = TokenId::SymAmpersand;
        else if (kind == LaneReduceKind::Or)
            opTokId = TokenId::SymPipe;
        else if (kind == LaneReduceKind::Xor)
            opTokId = TokenId::SymCircumflex;

        const MicroReg stepReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegReg(stepReg, accReg, upperReg, binaryMicroOpForLane(opTokId, laneType), MicroOpBits::B128);
        accReg = stepReg;
    }

    return accReg;
}

MicroReg CodeGenVectorHelpers::emitExtractLaneZero(CodeGen& codeGen, MicroReg vectorReg, const TypeInfo& laneType)
{
    // A scalar float already lives in the low lane of a vector register, so
    // the reduction result is the value.
    if (laneType.isFloat())
        return vectorReg;

    MicroBuilder&  builder  = codeGen.builder();
    const uint32_t laneBits = laneBitsOf(laneType);
    const bool     isSigned = laneType.isIntSigned();

    // A narrow lane widens inside the register file first: the move out of the
    // float file reads 32 bits, and the lanes above the first would otherwise
    // ride along.
    MicroReg srcReg = vectorReg;
    if (laneBits == 8)
    {
        const MicroReg wideReg = codeGen.nextVirtualFloatRegister();
        builder.emitVecUnaryRegReg(wideReg, srcReg, isSigned ? MicroOp::VecWidenLoS8 : MicroOp::VecWidenLoU8, MicroOpBits::B128);
        srcReg = wideReg;
    }

    if (laneBits <= 16)
    {
        const MicroReg wideReg = codeGen.nextVirtualFloatRegister();
        builder.emitVecUnaryRegReg(wideReg, srcReg, isSigned ? MicroOp::VecWidenLoS16 : MicroOp::VecWidenLoU16, MicroOpBits::B128);
        srcReg = wideReg;
    }

    const MicroReg dstReg = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegReg(dstReg, srcReg, laneBits == 64 ? MicroOpBits::B64 : MicroOpBits::B32);
    return dstReg;
}

MicroReg CodeGenVectorHelpers::emitSumAbsoluteDifferences(CodeGen& codeGen, MicroReg leftReg, MicroReg rightReg, const TypeInfo& laneType)
{
    MicroBuilder& builder = codeGen.builder();

    // Signed bytes reach the unsigned instruction by biasing both sides: the
    // difference of two values shifted by the same amount is unchanged.
    MicroReg left  = leftReg;
    MicroReg right = rightReg;
    if (laneType.isIntSigned())
    {
        const MicroReg biasReg = repeatedConstant(codeGen, 1, 0x80);
        const MicroReg leftBiasedReg = codeGen.nextVirtualFloatRegister();
        const MicroReg rightBiasedReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegReg(leftBiasedReg, leftReg, biasReg, MicroOp::VecXor, MicroOpBits::B128);
        builder.emitOpBinaryRegRegReg(rightBiasedReg, rightReg, biasReg, MicroOp::VecXor, MicroOpBits::B128);
        left  = leftBiasedReg;
        right = rightBiasedReg;
    }

    const MicroReg dstReg = codeGen.nextVirtualFloatRegister();
    builder.emitOpBinaryRegRegReg(dstReg, left, right, MicroOp::VecSadU8, MicroOpBits::B128);
    return dstReg;
}

namespace
{
    // The byte a lane index turns into: lane 'index' of a vector starts at
    // 'index * laneBytes', and the bytes of a lane follow in order.
    void fillLaneByteTable(std::array<uint8_t, 16>& outTable, std::span<const uint8_t> laneIndices, uint32_t laneBytes)
    {
        for (uint32_t lane = 0; lane < laneIndices.size(); ++lane)
        {
            for (uint32_t byteIndex = 0; byteIndex < laneBytes; ++byteIndex)
                outTable[lane * laneBytes + byteIndex] = static_cast<uint8_t>(laneIndices[lane] * laneBytes + byteIndex);
        }
    }

    // True when a byte table is exactly a permutation of 32-bit lanes, which
    // one immediate 'pshufd' performs.
    bool tryFourLaneControl(std::span<const uint8_t> table, uint8_t& outControl)
    {
        uint8_t control = 0;
        for (uint32_t lane = 0; lane < 4; ++lane)
        {
            const uint32_t first = table[lane * 4];
            if (first % 4 != 0 || first >= 16)
                return false;
            for (uint32_t byteIndex = 1; byteIndex < 4; ++byteIndex)
            {
                if (table[lane * 4 + byteIndex] != first + byteIndex)
                    return false;
            }

            control = static_cast<uint8_t>(control | ((first / 4) << (lane * 2)));
        }

        outControl = control;
        return true;
    }

    // Expands a runtime vector of lane indices into the byte table the dynamic
    // permute reads: mask the index into range, scale it to bytes, spread each
    // lane's low byte over the lane, and number the bytes inside it.
    MicroReg emitLaneIndexByteTable(CodeGen& codeGen, MicroReg patternReg, const TypeInfo& laneType, uint32_t laneCountMask)
    {
        const uint32_t laneBytes = laneBitsOf(laneType) / 8;
        const MicroReg maskedReg = emitVecBinary(codeGen, patternReg, repeatedConstant(codeGen, laneBytes, laneCountMask), MicroOp::VecAnd);
        if (laneBytes == 1)
            return maskedReg;

        const uint32_t shift    = laneBytes == 2 ? 1 : laneBytes == 4 ? 2 : 3;
        const MicroReg scaleReg = CodeGenVectorHelpers::emitLaneShiftImm(codeGen, maskedReg, laneType, shift, true);

        std::array<uint8_t, 16> spread{};
        std::array<uint8_t, 16> offsets{};
        for (uint32_t byteIndex = 0; byteIndex < 16; ++byteIndex)
        {
            spread[byteIndex]  = static_cast<uint8_t>((byteIndex / laneBytes) * laneBytes);
            offsets[byteIndex] = static_cast<uint8_t>(byteIndex % laneBytes);
        }

        const MicroReg spreadReg = emitVecBinary(codeGen, scaleReg, byteTableConstant(codeGen, spread), MicroOp::VecPermB);
        return emitVecBinary(codeGen, spreadReg, byteTableConstant(codeGen, offsets), MicroOp::VecAdd8);
    }

    // Selects bytes out of two vectors through one runtime byte table: an index
    // below sixteen reads the first vector, one below thirty-two the second,
    // and anything above answers zero.
    MicroReg emitTwoSourceByteSelect(CodeGen& codeGen, MicroReg firstReg, MicroReg secondReg, MicroReg tableReg, const TypeInfo& byteLaneType)
    {
        const MicroReg signBitReg = repeatedConstant(codeGen, 1, 0x80);
        const MicroReg lowLimit   = repeatedConstant(codeGen, 1, 15);
        const MicroReg highLimit  = repeatedConstant(codeGen, 1, 31);

        const MicroReg fromSecondReg = CodeGenVectorHelpers::emitCompare(codeGen, TokenId::SymGreater, tableReg, lowLimit, byteLaneType);
        const MicroReg outOfRangeReg = CodeGenVectorHelpers::emitCompare(codeGen, TokenId::SymGreater, tableReg, highLimit, byteLaneType);

        const MicroReg firstTableReg   = emitVecBinary(codeGen, tableReg, emitVecBinary(codeGen, fromSecondReg, signBitReg, MicroOp::VecAnd), MicroOp::VecOr);
        const MicroReg loweredReg      = emitVecBinary(codeGen, tableReg, repeatedConstant(codeGen, 1, 16), MicroOp::VecSub8);
        const MicroReg fromFirstReg    = emitVecBinary(codeGen, fromSecondReg, signBitReg, MicroOp::VecAndNot);
        const MicroReg outOfRangeBitReg = emitVecBinary(codeGen, outOfRangeReg, signBitReg, MicroOp::VecAnd);
        const MicroReg secondTableReg  = emitVecBinary(codeGen, emitVecBinary(codeGen, loweredReg, fromFirstReg, MicroOp::VecOr), outOfRangeBitReg, MicroOp::VecOr);

        const MicroReg firstPartReg  = emitVecBinary(codeGen, firstReg, firstTableReg, MicroOp::VecPermB);
        const MicroReg secondPartReg = emitVecBinary(codeGen, secondReg, secondTableReg, MicroOp::VecPermB);
        return emitVecBinary(codeGen, firstPartReg, secondPartReg, MicroOp::VecOr);
    }
}

MicroReg CodeGenVectorHelpers::emitConstantShuffle(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& laneType, std::span<const uint8_t> laneIndices)
{
    const uint32_t          laneBytes = laneBitsOf(laneType) / 8;
    std::array<uint8_t, 16> table{};
    fillLaneByteTable(table, laneIndices, laneBytes);

    // A permutation of 32-bit lanes is one immediate instruction; anything
    // else is one dynamic permute against a constant table.
    uint8_t control = 0;
    if (tryFourLaneControl(table, control))
    {
        const MicroReg dstReg = codeGen.nextVirtualFloatRegister();
        codeGen.builder().emitVecShuffleRegRegImm(dstReg, valueReg, control, MicroOpBits::B128);
        return dstReg;
    }

    return emitVecBinary(codeGen, valueReg, byteTableConstant(codeGen, table), MicroOp::VecPermB);
}

MicroReg CodeGenVectorHelpers::emitDynamicShuffle(CodeGen& codeGen, MicroReg valueReg, MicroReg patternReg, const TypeInfo& laneType)
{
    const uint32_t laneCount = 16 / (laneBitsOf(laneType) / 8);
    const MicroReg tableReg  = emitLaneIndexByteTable(codeGen, patternReg, laneType, laneCount - 1);
    return emitVecBinary(codeGen, valueReg, tableReg, MicroOp::VecPermB);
}

MicroReg CodeGenVectorHelpers::emitConstantShuffle2(CodeGen& codeGen, MicroReg firstReg, MicroReg secondReg, const TypeInfo& laneType, std::span<const uint8_t> laneIndices)
{
    const uint32_t laneBytes = laneBitsOf(laneType) / 8;
    const uint32_t laneCount = 16 / laneBytes;

    // A pattern that never crosses into the other vector is a one-source
    // permutation, and the second source never has to be read.
    bool usesFirst  = false;
    bool usesSecond = false;
    for (uint32_t lane = 0; lane < laneCount; ++lane)
    {
        if (laneIndices[lane] < laneCount)
            usesFirst = true;
        else
            usesSecond = true;
    }

    if (!usesSecond)
        return emitConstantShuffle(codeGen, firstReg, laneType, laneIndices);

    std::array<uint8_t, 16> lowered{};
    for (uint32_t lane = 0; lane < laneCount; ++lane)
        lowered[lane] = static_cast<uint8_t>(laneIndices[lane] - laneCount);
    if (!usesFirst)
        return emitConstantShuffle(codeGen, secondReg, laneType, {lowered.data(), laneCount});

    // Four 32-bit lanes taking their low half from one vector and their high
    // half from the other is exactly what 'shufps' does.
    if (laneBytes == 4 && laneIndices[0] < 4 && laneIndices[1] < 4 && laneIndices[2] >= 4 && laneIndices[3] >= 4)
    {
        const uint8_t control = static_cast<uint8_t>(laneIndices[0] | (laneIndices[1] << 2) | ((laneIndices[2] - 4) << 4) | ((laneIndices[3] - 4) << 6));
        const MicroReg dstReg = codeGen.nextVirtualFloatRegister();
        codeGen.builder().emitOpTernaryRegRegRegImm(dstReg, firstReg, secondReg, control, MicroOp::VecShufF32, MicroOpBits::B128);
        return dstReg;
    }

    // Otherwise both sources are permuted against a constant table whose
    // out-of-range bytes select nothing, and the halves merge.
    std::array<uint8_t, 16> firstTable{};
    std::array<uint8_t, 16> secondTable{};
    for (uint32_t lane = 0; lane < laneCount; ++lane)
    {
        const bool fromFirst = laneIndices[lane] < laneCount;
        for (uint32_t byteIndex = 0; byteIndex < laneBytes; ++byteIndex)
        {
            const uint32_t position = lane * laneBytes + byteIndex;
            firstTable[position]    = fromFirst ? static_cast<uint8_t>(laneIndices[lane] * laneBytes + byteIndex) : 0x80;
            secondTable[position]   = fromFirst ? 0x80 : static_cast<uint8_t>(lowered[lane] * laneBytes + byteIndex);
        }
    }

    const MicroReg firstPartReg  = emitVecBinary(codeGen, firstReg, byteTableConstant(codeGen, firstTable), MicroOp::VecPermB);
    const MicroReg secondPartReg = emitVecBinary(codeGen, secondReg, byteTableConstant(codeGen, secondTable), MicroOp::VecPermB);
    return emitVecBinary(codeGen, firstPartReg, secondPartReg, MicroOp::VecOr);
}

MicroReg CodeGenVectorHelpers::emitDynamicShuffle2(CodeGen& codeGen, MicroReg firstReg, MicroReg secondReg, MicroReg patternReg, const TypeInfo& laneType, const TypeInfo& byteLaneType)
{
    const uint32_t laneCount = 16 / (laneBitsOf(laneType) / 8);
    const MicroReg tableReg  = emitLaneIndexByteTable(codeGen, patternReg, laneType, laneCount * 2 - 1);
    return emitTwoSourceByteSelect(codeGen, firstReg, secondReg, tableReg, byteLaneType);
}

MicroReg CodeGenVectorHelpers::emitConstantAlign(CodeGen& codeGen, MicroReg lowReg, MicroReg highReg, uint32_t count)
{
    MicroBuilder& builder = codeGen.builder();
    if (!count)
    {
        const MicroReg copyReg = codeGen.nextVirtualFloatRegister();
        builder.emitLoadRegReg(copyReg, lowReg, MicroOpBits::B128);
        return copyReg;
    }

    if (count >= 32)
    {
        const MicroReg zeroReg = codeGen.nextVirtualFloatRegister();
        builder.emitOpBinaryRegRegReg(zeroReg, lowReg, lowReg, MicroOp::VecXor, MicroOpBits::B128);
        return zeroReg;
    }

    // 'palignr' concatenates its first source above its second and slides the
    // window down, which is the whole operation.
    const MicroReg dstReg = codeGen.nextVirtualFloatRegister();
    builder.emitOpTernaryRegRegRegImm(dstReg, highReg, lowReg, static_cast<uint8_t>(count), MicroOp::VecAlignR, MicroOpBits::B128);
    return dstReg;
}

MicroReg CodeGenVectorHelpers::emitDynamicAlign(CodeGen& codeGen, MicroReg lowReg, MicroReg highReg, MicroReg countReg, const TypeInfo& byteLaneType)
{
    // The window starts at 'count' and numbers sixteen bytes from there. The
    // saturating add keeps a large count out of range instead of wrapping it
    // back into the window.
    const MicroReg countVecReg = splatScalarLane(codeGen, countReg, byteLaneType);

    std::array<uint8_t, 16> offsets{};
    for (uint32_t byteIndex = 0; byteIndex < 16; ++byteIndex)
        offsets[byteIndex] = static_cast<uint8_t>(byteIndex);

    const MicroReg tableReg = emitVecBinary(codeGen, countVecReg, byteTableConstant(codeGen, offsets), MicroOp::VecSatAddU8);
    return emitTwoSourceByteSelect(codeGen, lowReg, highReg, tableReg, byteLaneType);
}

SWC_END_NAMESPACE();
