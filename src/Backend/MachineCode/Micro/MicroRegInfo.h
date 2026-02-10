#pragma once
#include "Backend/MachineCode/Micro/MicroInstr.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class Encoder;

struct MicroRegUseDef
{
    SmallVector<MicroReg, 6> uses;
    SmallVector<MicroReg, 3> defs;
    bool                     isCall   = false;
    CallConvKind             callConv = CallConvKind::C;

    void addUse(MicroReg reg);
    void addDef(MicroReg reg);
    void addUseDef(MicroReg reg);
};

struct MicroRegOperandRef
{
    MicroReg* reg = nullptr;
    bool      use = false;
    bool      def = false;
};

class MicroRegInfo
{
public:
    static MicroRegUseDef collectUseDef(const MicroInstr& inst, const PagedStore& store, const Encoder* encoder);
    static void           collectRegOperands(const MicroInstr& inst, PagedStore& store, SmallVector<MicroRegOperandRef, 8>& out, const Encoder* encoder);
};

SWC_END_NAMESPACE();
