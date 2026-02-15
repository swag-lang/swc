#include "pch.h"
#include "Backend/Unittest/BackendUnittestHelpers.h"
#include "Backend/CodeGen/Micro/MicroInstr.h"
#include "Backend/CodeGen/Micro/Passes/MicroLegalizePass.h"
#include "Backend/CodeGen/Micro/Passes/MicroEncodePass.h"
#include "Backend/CodeGen/Micro/Passes/MicroPass.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace Backend::Unittest
{
    Result parseExpected(const char* text, std::vector<ExpectedByte>& result)
    {
        if (!text || !*text)
            return Result::Continue;

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
                if (token.size() != 2)
                    return Result::Error;
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
                        return Result::Error;
                    value = (value << 4) | nibble;
                }

                result.push_back(ExpectedByte{static_cast<uint8_t>(value), false});
            }

            token.clear();
            if (!c)
                break;
        }

        return Result::Continue;
    }

    Result runEncodeCase(TaskContext& ctx, Encoder& encoder, const char* name, const char* expectedHex, const std::function<void(MicroInstrBuilder&)>& fn)
    {
        MicroInstrBuilder builder(ctx);
        fn(builder);

        MicroLegalizePass legalizePass;
        MicroEncodePass   encodePass;
        MicroPassManager  passes;
        passes.add(legalizePass);
        passes.add(encodePass);

        MicroPassContext passCtx;
        builder.runPasses(passes, &encoder, passCtx);

        if (encoder.size() == 0)
        {
            Logger::print(ctx, std::format("runEncodeCase empty output: case={}\n", name));
            return Result::Error;
        }

        const auto                size = encoder.size();
        std::vector<ExpectedByte> expected;
        if (parseExpected(expectedHex, expected) != Result::Continue)
        {
            Logger::print(ctx, std::format("runEncodeCase invalid expected pattern: case={}\n", name));
            return Result::Error;
        }

        if (size != expected.size())
        {
            Logger::print(ctx, std::format("runEncodeCase size mismatch: case={} expected={} got={}\n", name, expected.size(), size));
            return Result::Error;
        }

        for (uint32_t i = 0; i < size; ++i)
        {
            if (!expected[i].wildcard)
            {
                const auto got = encoder.byteAt(i);
                if (got != expected[i].value)
                {
                    Logger::print(ctx, std::format("runEncodeCase mismatch: case={} byte={} expected={:02X} got={:02X}\n", name, i, expected[i].value, got));
                    return Result::Error;
                }
            }
        }

        return Result::Continue;
    }

    bool isPersistentReg(const SmallVector<MicroReg>& regs, MicroReg reg)
    {
        return std::ranges::find(regs, reg) != regs.end();
    }

    Result assertNoVirtualRegs(MicroInstrBuilder& builder)
    {
        auto& storeOps = builder.operands();
        for (const auto& inst : builder.instructions().view())
        {
            SmallVector<MicroInstrRegOperandRef> regs;
            inst.collectRegOperands(storeOps, regs, nullptr);
            for (const auto& regRef : regs)
            {
                if (!regRef.reg || regRef.reg->isVirtual())
                    return Result::Error;
            }
        }

        return Result::Continue;
    }
}

#endif

SWC_END_NAMESPACE();
