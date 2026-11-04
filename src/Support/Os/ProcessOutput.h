#pragma once
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

namespace Os
{
    // Owns capture and complete-line delivery independently of the host pipe mechanism.
    class ProcessOutput
    {
    public:
        explicit ProcessOutput(const ProcessRunOptions* options) : options_(options) {}
        bool needsPipe() const;
        void append(std::string_view bytes);
        void flush();

    private:
        void emit(std::string_view line) const;

        const ProcessRunOptions* options_ = nullptr;
        std::string              pendingLine_;
    };
}

SWC_END_NAMESPACE();
