#pragma once
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroTypes.h"
#include "Support/Core/Store.h"

#include <array>

SWC_BEGIN_NAMESPACE();

enum class MicroInstrRegMode : uint8_t
{
    None,
    Use,
    Def,
    UseDef,
};

enum class MicroInstrRegSpecial : uint8_t
{
    None,
    OpBinaryRegReg,
    OpBinaryMemReg,
    OpTernaryRegRegReg,
};

struct MicroInstrRegInfo
{
    std::array<MicroInstrRegMode, 3> regModes;
    MicroInstrRegSpecial             special       = MicroInstrRegSpecial::None;
    uint8_t                          microOpIndex  = 0;
    bool                             isCall        = false;
    uint8_t                          callConvIndex = 0;
};

struct MicroInstrOpcodeInfo
{
    MicroInstrRegInfo regInfo;
};

enum class MicroInstrOpcode : uint8_t
{
#define SWC_MICRO_INSTR_DEF(__enum, ...) __enum,
#include "Backend/MachineCode/Micro/MicroInstr.Def.inc"

#undef SWC_MICRO_INSTR_DEF
};

constexpr std::array MICRO_INSTR_OPCODE_INFOS = {
#define SWC_MICRO_INSTR_DEF(__enum, ...) __VA_ARGS__,
#include "Backend/MachineCode/Micro/MicroInstr.Def.inc"

#undef SWC_MICRO_INSTR_DEF
};

static_assert(MICRO_INSTR_OPCODE_INFOS.size() == static_cast<size_t>(MicroInstrOpcode::OpTernaryRegRegReg) + 1);

struct MicroInstrOperand
{
    union
    {
        IdentifierRef name;
        CallConvKind  callConv;
        MicroReg      reg;
        MicroOpBits   opBits;
        MicroCond     cpuCond;
        MicroCondJump jumpType;
        MicroOp       microOp;
        uint32_t      valueU32;
        int32_t       valueI32;
        uint64_t      valueU64;
    };

    MicroInstrOperand() :
        valueU64(0)
    {
    }

    MicroInstrOperand(const MicroInstrOperand& other)
    {
        std::memcpy(this, &other, sizeof(MicroInstrOperand));
    }

    MicroInstrOperand& operator=(const MicroInstrOperand& other)
    {
        if (this != &other)
            std::memcpy(this, &other, sizeof(MicroInstrOperand));
        return *this;
    }
};

struct MicroInstr
{
    Ref              opsRef      = INVALID_REF;
    MicroInstrOpcode op          = MicroInstrOpcode::OpBinaryRegImm;
    EncodeFlags      emitFlags   = EncodeFlagsE::Zero;
    uint8_t          numOperands = 0;

    MicroInstrOperand* ops(Store& store) const
    {
        if (!numOperands)
            return nullptr;
        return store.ptr<MicroInstrOperand>(opsRef);
    }

    const MicroInstrOperand* ops(const Store& store) const
    {
        if (!numOperands)
            return nullptr;
        return store.ptr<MicroInstrOperand>(opsRef);
    }

    static constexpr const MicroInstrOpcodeInfo& info(MicroInstrOpcode op) { return MICRO_INSTR_OPCODE_INFOS[static_cast<size_t>(op)]; }
};

SWC_END_NAMESPACE();
