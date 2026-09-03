#pragma once
#include "Backend/ABI/CallConv.h"
#include "Backend/Encoder/EncoderDebugInfo.h"
#include "Backend/Micro/MicroTypes.h"
#include "Support/Core/Flags.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/SmallVector.h"
#include "Support/Math/ApInt.h"

SWC_BEGIN_NAMESPACE();

class Encoder;
class MicroOperandStorage;

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

enum class MicroInstrFlagsE : uint16_t
{
    Zero                     = 0,
    TerminatorInstruction    = 1 << 0,
    JumpInstruction          = 1 << 1,
    ConditionalJump          = 1 << 2,
    UsesCpuFlags             = 1 << 3,
    DefinesCpuFlags          = 1 << 4,
    HasMemBaseOffsetOperands = 1 << 5,
    IsCallInstruction        = 1 << 6,
    WritesMemory             = 1 << 7,
};
using MicroInstrFlags = EnumFlags<MicroInstrFlagsE>;

struct MicroInstrDef
{
    std::array<MicroInstrRegMode, 3> regModes;
    MicroInstrRegSpecial             special               = MicroInstrRegSpecial::None;
    uint8_t                          microOpIndex          = 0;
    uint8_t                          callConvIndex         = 0;
    MicroInstrFlags                  flags                 = MicroInstrFlagsE::Zero;
    uint8_t                          memBaseOperandIndex   = 0;
    uint8_t                          memOffsetOperandIndex = 0;
};

// Register width contract, inherited from x86-64: an integer instruction with
// a 32-bit operand size writes its whole 64-bit destination and clears the
// upper half, while 8- and 16-bit writes leave the rest of the register as it
// was. Passes may rely on it - a value defined at 32 bits reads as its own
// zero-extension at 64 - and every rewrite that changes an operand size has to
// keep it: widening a 32-bit definition to 64 bits changes what its readers see.
enum class MicroInstrOpcode : uint8_t
{
#define SWC_MICRO_INSTR_DEF(__enum, ...) __enum,
#include "Backend/Micro/MicroInstr.Def.inc"

#undef SWC_MICRO_INSTR_DEF
};

inline constexpr std::array MICRO_INSTR_OPCODE_INFOS = {
#define SWC_MICRO_INSTR_DEF(__enum, ...) __VA_ARGS__,
#include "Backend/Micro/MicroInstr.Def.inc"

#undef SWC_MICRO_INSTR_DEF
};

static_assert(MICRO_INSTR_OPCODE_INFOS.size() == static_cast<size_t>(MicroInstrOpcode::JumpTableData) + 1);

struct MicroInstrOperand
{
    union
    {
        IdentifierRef name;
        CallConvKind  callConv;
        MicroReg      reg;
        MicroOpBits   opBits;
        MicroCond     cpuCond;
        MicroOp       microOp;
        uint32_t      valueU32;
        int32_t       valueI32;
        uint64_t      valueU64;
    };

    ApInt valueInt;

    MicroInstrOperand() :
        valueU64(0),
        valueInt(uint64_t{0}, 64)
    {
    }

    void setImmediateValue(const ApInt& value)
    {
        valueInt = value;
        valueU64 = value.as64();
    }

    bool hasWideImmediateValue() const
    {
        return valueInt.bitWidth() > 64 && valueInt.as64() == valueU64;
    }

    const ApInt& wideImmediateValue() const
    {
        return valueInt;
    }

    ApInt immediateValue(uint32_t fallbackBitWidth = 64) const
    {
        if (hasWideImmediateValue())
            return valueInt;
        return ApInt(valueU64, fallbackBitWidth);
    }
};

struct MicroInstrUseDef
{
    SmallVector4<MicroReg> uses;
    SmallVector4<MicroReg> defs;
    bool                   isCall   = false;
    CallConvKind           callConv = CallConvKind::Swag;

    void addUse(MicroReg reg);
    void addDef(MicroReg reg);
    void addUseDef(MicroReg reg);
};

struct MicroInstrRegOperandRef
{
    MicroReg* reg = nullptr;
    bool      use = false;
    bool      def = false;
};

struct MicroInstr
{
    DebugSourceInfo  debugSourceInfo;
    MicroOperandRef  opsRef      = MicroOperandRef::invalid();
    MicroInstrOpcode op          = MicroInstrOpcode::OpBinaryRegImm;
    uint8_t          numOperands = 0;

    MicroInstrOperand*       ops(MicroOperandStorage& operands) const;
    const MicroInstrOperand* ops(const MicroOperandStorage& operands) const;
    MicroInstrUseDef         collectUseDef(const MicroOperandStorage& operands, const Encoder* encoder) const;
    void                     collectRegOperands(MicroOperandStorage& operands, SmallVector<MicroInstrRegOperandRef>& out, const Encoder* encoder) const;

    static constexpr const MicroInstrDef& info(MicroInstrOpcode op) { return MICRO_INSTR_OPCODE_INFOS[static_cast<size_t>(op)]; }
};

SWC_END_NAMESPACE();
