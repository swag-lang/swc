#include "pch.h"
#include "Backend/Backend.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Encoder/X64Encoder.h"
#include "Backend/MachineCode/Micro/MicroInstr.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Backend/MachineCode/Micro/Passes/MicroEncodePass.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"
#include "Backend/MachineCode/Micro/Passes/MicroRegAllocPass.h"
#include "Main/CommandLine.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

#if SWC_DEV_MODE

namespace Backend
{
    class TestX64Encoder final : public X64Encoder
    {
    public:
        explicit TestX64Encoder(TaskContext& ctx) :
            X64Encoder(ctx)
        {
        }

        uint32_t size() const
        {
            return store_.size();
        }

        const uint8_t* data() const
        {
            if (!store_.size())
                return nullptr;
            return store_.ptr<uint8_t>(0);
        }
    };

    using BackendTestFn = void (*)(TaskContext&);

    struct BackendTestCase
    {
        const char*   name;
        BackendTestFn fn;
    };

    static bool isPersistentReg(const SmallVector<MicroReg>& regs, MicroReg reg)
    {
        return std::ranges::find(regs, reg) != regs.end();
    }

    static void assertNoVirtualRegs(MicroInstrBuilder& builder)
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

    static void testRegAllocPersistentAcrossCall(TaskContext& ctx)
    {
        MicroInstrBuilder builder(ctx);
        const auto        vLive = MicroReg::virtualIntReg(0);
        const auto        vTemp = MicroReg::virtualIntReg(1);

        builder.encodeLoadRegImm(vLive, 0x11, MicroOpBits::B64, EncodeFlagsE::Zero);
        builder.encodeLoadRegImm(vTemp, 0x22, MicroOpBits::B64, EncodeFlagsE::Zero);
        builder.encodeOpBinaryRegImm(vTemp, 1, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
        builder.encodeCallReg(MicroReg::intReg(0), CallConvKind::C, EncodeFlagsE::Zero);
        builder.encodeOpBinaryRegImm(vLive, 2, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);

        MicroRegAllocPass regAllocPass;
        MicroPassManager  passes;
        passes.add(regAllocPass);

        MicroPassContext passCtx;
        builder.runPasses(passes, nullptr, passCtx);

        assertNoVirtualRegs(builder);

        const auto& conv = CallConv::get(CallConvKind::C);
        auto&       ops  = builder.operands().store();

        const MicroInstr* firstInst  = nullptr;
        const MicroInstr* secondInst = nullptr;
        for (const auto& inst : builder.instructions().view())
        {
            if (!firstInst)
            {
                firstInst = &inst;
                continue;
            }

            secondInst = &inst;
            break;
        }

        SWC_ASSERT(firstInst);
        SWC_ASSERT(secondInst);
        const auto* firstOps  = firstInst->ops(ops);
        const auto* secondOps = secondInst->ops(ops);
        SWC_ASSERT(firstOps && secondOps);

        const MicroReg regLive = firstOps[0].reg;
        const MicroReg regTemp = secondOps[0].reg;
        SWC_ASSERT(regLive.isInt());
        SWC_ASSERT(regTemp.isInt());
        SWC_ASSERT(isPersistentReg(conv.intPersistentRegs, regLive));
        SWC_ASSERT(!isPersistentReg(conv.intPersistentRegs, regTemp));
    }

    static void testEncodeSimpleSequence(TaskContext& ctx)
    {
        MicroInstrBuilder builder(ctx);

        builder.encodeLoadRegImm(MicroReg::intReg(0), 0x1234, MicroOpBits::B64, EncodeFlagsE::Zero);
        builder.encodeOpBinaryRegReg(MicroReg::intReg(0), MicroReg::intReg(1), MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
        builder.encodeRet(EncodeFlagsE::Zero);

        TestX64Encoder  encoder(ctx);
        MicroEncodePass encodePass;
        MicroPassManager passes;
        passes.add(encodePass);

        MicroPassContext passCtx;
        builder.runPasses(passes, &encoder, passCtx);

        SWC_ASSERT(encoder.size() > 0);
        SWC_ASSERT(encoder.data());
    }

    static constexpr std::array K_BACKEND_TESTS = {
        BackendTestCase{"RegAllocPersistentAcrossCall", &testRegAllocPersistentAcrossCall},
        BackendTestCase{"EncodeSimpleSequence", &testEncodeSimpleSequence},
    };

    void test(const Global& global, const CommandLine& cmdLine)
    {
        CallConv::setup();
        TaskContext ctx(global, cmdLine);

        for (const auto& testCase : K_BACKEND_TESTS)
        {
            SWC_ASSERT(testCase.name);
            SWC_ASSERT(testCase.fn);
            testCase.fn(ctx);
        }
    }
}

#else

namespace Backend
{
    void test(const Global&, const CommandLine&)
    {
    }
}

#endif

SWC_END_NAMESPACE();
