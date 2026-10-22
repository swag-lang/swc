#pragma once
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

// Only ever named through a reference here; the encoder tests include the concrete
// encoder they drive.
class Encoder;

namespace Backend::Unittest
{
    struct ExpectedByte
    {
        uint8_t value    = 0;
        bool    wildcard = false;
    };

    Result parseExpected(const char* text, std::vector<ExpectedByte>& result);

    // Runs one pass over what the builder holds, in a default Swag-convention context.
    template<typename PASS>
    Result runMicroPass(MicroBuilder& builder, Encoder* encoder = nullptr, CallConvKind callConv = CallConvKind::Swag)
    {
        PASS             pass;
        MicroPassManager passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = callConv;
        return builder.runPasses(passManager, encoder, passContext);
    }

    Result runEncodeCase(TaskContext& ctx, Encoder& encoder, const char* name, const char* expectedHex, const std::function<void(MicroBuilder&)>& fn);

    // Execute encoder-conforming physical IR with one C-ABI data pointer.
    Result executeMicroCase(TaskContext& ctx, MicroBuilder& builder, uint64_t* values);

    bool   isPersistentReg(MicroRegSpan regs, MicroReg reg);
    Result assertNoVirtualRegs(MicroBuilder& builder);
    // How many times an opcode occurs in what the builder has emitted so far.
    uint32_t          countOpcode(const MicroBuilder& builder, MicroInstrOpcode opcode);
    const MicroInstr* findFirstOpcode(const MicroBuilder& builder, MicroInstrOpcode opcode);
    uint32_t          countBinaryRegRegOp(const MicroBuilder& builder, MicroOp op);
    // First linear position of an opcode, or UINT32_MAX.
    uint32_t firstOpcodePosition(const MicroBuilder& builder, MicroInstrOpcode opcode);
    bool     isStackAdjust(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg stackPointer, MicroOp expectedOp, uint64_t expectedImmediate);
}

#endif

SWC_END_NAMESPACE();
