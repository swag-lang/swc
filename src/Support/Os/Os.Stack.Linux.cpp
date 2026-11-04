#include "pch.h"
#include "Support/Os/Os.h"

#ifdef __linux__
#include <cxxabi.h>
#include <dlfcn.h>
#include <unwind.h>

SWC_BEGIN_NAMESPACE();

namespace
{
    struct StackCapture
    {
        std::span<uintptr_t> frames;
        uint64_t             skip;
        uint32_t             count = 0;
    };

    _Unwind_Reason_Code captureFrame(_Unwind_Context* context, void* userData)
    {
        auto& capture = *static_cast<StackCapture*>(userData);
        if (capture.skip)
        {
            --capture.skip;
            return _URC_NO_REASON;
        }
        const uintptr_t address = _Unwind_GetIP(context);
        if (!address)
            return _URC_END_OF_STACK;
        capture.frames[capture.count++] = address;
        return capture.count == capture.frames.size() ? _URC_END_OF_STACK : _URC_NO_REASON;
    }
}

uint32_t Os::captureCallStack(const std::span<uintptr_t> outFrames, const uint32_t skipFrames)
{
    if (outFrames.empty())
        return 0;
    // Match the Windows diagnostic cap, without allocating or limiting the requested skip.
    StackCapture capture{outFrames.first(std::min<size_t>(outFrames.size(), 64)), static_cast<uint64_t>(skipFrames) + 1};
    _Unwind_Backtrace(captureFrame, &capture);
    return capture.count;
}

bool Os::resolveAddress(ResolvedAddress& outAddress, const uintptr_t address, const TaskContext* ctx)
{
    SWC_UNUSED(ctx);
    outAddress = {};
    Dl_info info{};
    if (!address || !dladdr(reinterpret_cast<const void*>(address), &info))
        return false;
    if (info.dli_fname)
        outAddress.moduleName = info.dli_fname;
    if (info.dli_sname)
    {
        int status = 0;
        char* demangled = abi::__cxa_demangle(info.dli_sname, nullptr, nullptr, &status);
        outAddress.symbolName = status == 0 && demangled ? demangled : info.dli_sname;
        std::free(demangled);
    }
    // dladdr resolves loaded ELF images and exported symbols, not DWARF source locations.
    return !outAddress.moduleName.empty() || !outAddress.symbolName.empty();
}

SWC_END_NAMESPACE();
#endif
