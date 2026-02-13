#include "pch.h"
#include "Backend/Unittest/BackendUnittestHelpers.h"
#include "Backend/MachineCode/Micro/MicroInstr.h"
#include "Backend/MachineCode/Micro/Passes/MicroEncodePass.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace Backend::Unittest
{
    std::vector<ExpectedByte> parseExpected(const char* text)
    {
        std::vector<ExpectedByte> result;
        if (!text || !*text)
            return result;

        std::string token;
        for (const char* p = text;; ++p)
        {
            const char c = *p;
            if (c && c != ' ' && c != '\t' && c != '\n' && c != '\r')
            {
                token.push_back(c);
                continue;
            }

            if (token.empty())
            {
                if (!c)
                    break;
                continue;
            }

            if (token == "??")
            {
                result.push_back(ExpectedByte{0, true});
            }
            else
            {
                SWC_ASSERT(token.size() == 2);
                uint32_t value = 0;
                for (const auto tc : token)
                {
                    uint32_t nibble = 0;
                    if (tc >= '0' && tc <= '9')
                        nibble = static_cast<uint32_t>(tc - '0');
                    else if (tc >= 'a' && tc <= 'f')
                        nibble = static_cast<uint32_t>(10 + tc - 'a');
                    else if (tc >= 'A' && tc <= 'F')
                        nibble = static_cast<uint32_t>(10 + tc - 'A');
                    else
                        SWC_ASSERT(false);
                    value = (value << 4) | nibble;
                }

                result.push_back(ExpectedByte{static_cast<uint8_t>(value), false});
            }

            token.clear();
            if (!c)
                break;
        }

        return result;
    }

    void runEncodeCase(TaskContext& ctx, Encoder& encoder, const char* name, const char* expectedHex, const std::function<void(MicroInstrBuilder&)>& fn)
    {
        MicroInstrBuilder builder(ctx);
        fn(builder);

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
                    Logger::print(ctx, std::format("runEncodeCase mismatch: case={} byte={} expected={:02X} got={:02X}\n", name, i, expected[i].value, got));
                    SWC_ASSERT(false);
                }
            }
        }
    }

    bool isPersistentReg(const SmallVector<MicroReg>& regs, MicroReg reg)
    {
        return std::ranges::find(regs, reg) != regs.end();
    }

    void assertNoVirtualRegs(MicroInstrBuilder& builder)
    {
        auto& storeOps = builder.operands().store();
        for (const auto& inst : builder.instructions().view())
        {
            SmallVector<MicroInstrRegOperandRef> regs;
            inst.collectRegOperands(storeOps, regs, nullptr);
            for (const auto& regRef : regs)
                SWC_ASSERT(regRef.reg && !regRef.reg->isVirtual());
        }
    }
}

SWC_END_NAMESPACE();
