#pragma once
#include "Backend/MachineCode/Encoder/X64Encoder.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Backend/MachineCode/Micro/Passes/MicroEncodePass.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace Backend::Unittest
{
    struct ExpectedByte
    {
        uint8_t value    = 0;
        bool    wildcard = false;
    };

    std::vector<ExpectedByte> parseExpected(const char* text);

    template<typename F>
    void runEncodeCase(TaskContext& ctx, const char* name, const char* expectedHex, F&& fn)
    {
        MicroInstrBuilder builder(ctx);
        fn(builder);

        X64Encoder       encoder(ctx);
        MicroEncodePass  encodePass;
        MicroPassManager passes;
        passes.add(encodePass);

        MicroPassContext passCtx;
        builder.runPasses(passes, &encoder, passCtx);

        SWC_ASSERT(encoder.size() > 0);
        const auto size     = encoder.size();
        const auto expected = parseExpected(expectedHex);
        SWC_ASSERT(size == expected.size());
        for (uint32_t i = 0; i < size; ++i)
        {
            if (!expected[i].wildcard)
            {
                const auto got = encoder.byteAt(i);
                if (got != expected[i].value)
                {
                    Logger::print(ctx, std::format("EncodeAllInstructionsX64 mismatch: case={} byte={} expected={:02X} got={:02X}\n", name, i, expected[i].value, got));

                    std::string encoded = "Encoded bytes: ";
                    for (uint32_t j = 0; j < size; ++j)
                    {
                        encoded += std::format("{:02X}", encoder.byteAt(j));
                        if (j + 1 < size)
                            encoded += " ";
                    }
                    encoded += "\n";
                    Logger::print(ctx, encoded);

                    Logger::print(ctx, std::format("Expected: {}\n", expectedHex));
                    SWC_ASSERT(false);
                }
            }
        }
    }

    bool isPersistentReg(const SmallVector<MicroReg>& regs, MicroReg reg);
    void assertNoVirtualRegs(MicroInstrBuilder& builder);
}

SWC_END_NAMESPACE();
