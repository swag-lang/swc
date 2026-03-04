#include "pch.h"
#include "Backend/Encoder/X64Unwind.h"
#include "Backend/Encoder/X64Unwind.Windows.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class X64UnwindUnsupported final : public X64Unwind
    {
    public:
        void buildInfo(std::vector<std::byte>& outUnwindInfo, const uint32_t codeSize) const override
        {
            SWC_UNUSED(codeSize);
            outUnwindInfo.clear();
            SWC_FORCE_ASSERT(false && "X64 unwind info is not implemented for this target OS");
        }

        void onInstructionEncoded(const MicroInstr& inst, const MicroInstrOperand* ops, const uint32_t codeStartOffset, const uint32_t codeEndOffset) override
        {
            SWC_UNUSED(inst);
            SWC_UNUSED(ops);
            SWC_UNUSED(codeStartOffset);
            SWC_UNUSED(codeEndOffset);
        }
    };
}

std::unique_ptr<X64Unwind> X64Unwind::create(const Runtime::TargetOs targetOs)
{
    switch (targetOs)
    {
        case Runtime::TargetOs::Windows:
            return std::make_unique<X64UnwindWindows>();

        case Runtime::TargetOs::Linux:
            return std::make_unique<X64UnwindUnsupported>();

        default:
            return std::make_unique<X64UnwindUnsupported>();
    }
}

SWC_END_NAMESPACE();
