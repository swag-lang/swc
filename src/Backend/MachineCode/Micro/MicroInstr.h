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
#define SWC_MICRO_INSTR_DEF(__enum, __info) __enum,
#include "Backend/MachineCode/Micro/MicroInstr.Def.inc"

#undef SWC_MICRO_INSTR_DEF
};

#define MICRO_REG_NONE   MicroInstrRegMode::None
#define MICRO_REG_USE    MicroInstrRegMode::Use
#define MICRO_REG_DEF    MicroInstrRegMode::Def
#define MICRO_REG_USEDEF MicroInstrRegMode::UseDef

#define MICRO_INSTR_INFO(__r0, __r1, __r2, __special, __microOpIndex, __isCall, __callConvIndex) \
    MicroInstrOpcodeInfo                                                                         \
    {                                                                                            \
        MicroInstrRegInfo                                                                        \
        {                                                                                        \
            {__r0, __r1, __r2}, __special, __microOpIndex, __isCall, __callConvIndex             \
        }                                                                                        \
    }

#define MICRO_INSTR_SIMPLE(__r0, __r1, __r2) \
    MICRO_INSTR_INFO(__r0, __r1, __r2, MicroInstrRegSpecial::None, 0, false, 0)

#define MICRO_INSTR_CALL(__r0, __r1, __r2, __callConvIndex) \
    MICRO_INSTR_INFO(__r0, __r1, __r2, MicroInstrRegSpecial::None, 0, true, __callConvIndex)

#define MICRO_INSTR_SPECIAL(__r0, __r1, __r2, __special, __microOpIndex) \
    MICRO_INSTR_INFO(__r0, __r1, __r2, __special, __microOpIndex, false, 0)

constexpr std::array MICRO_INSTR_OPCODE_INFOS = {
#define SWC_MICRO_INSTR_DEF(__enum, __info) __info,
#include "Backend/MachineCode/Micro/MicroInstr.Def.inc"

#undef SWC_MICRO_INSTR_DEF
};

#undef MICRO_INSTR_SPECIAL
#undef MICRO_INSTR_CALL
#undef MICRO_INSTR_SIMPLE
#undef MICRO_INSTR_INFO
#undef MICRO_REG_USEDEF
#undef MICRO_REG_DEF
#undef MICRO_REG_USE
#undef MICRO_REG_NONE

constexpr const MicroInstrOpcodeInfo& getMicroInstrOpcodeInfo(MicroInstrOpcode op)
{
    return MICRO_INSTR_OPCODE_INFOS[static_cast<size_t>(op)];
}

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

    bool isEnd() const { return op == MicroInstrOpcode::End; }
};

SWC_END_NAMESPACE();
