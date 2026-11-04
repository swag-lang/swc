#include "pch.h"
#include "Support/Os/Os.h"
#include "Support/Os/Os.Exception.Linux.h"
#include "Support/Report/HardwareException.h"

#ifdef __linux__
#include <signal.h>

SWC_BEGIN_NAMESPACE();

void Os::decodeHostException(uint32_t& outExceptionCode, const void*& outExceptionAddress, const void* platformExceptionPointers)
{
    const auto* exception = static_cast<const LinuxException*>(platformExceptionPointers);
    outExceptionCode = exception ? exception->signal : 0;
    outExceptionAddress = exception ? reinterpret_cast<const void*>(exception->instructionAddress) : nullptr;
}

void Os::appendHostExceptionSummary(const TaskContext* ctx, Utf8& outMsg, const void* platformExceptionPointers)
{
    SWC_UNUSED(ctx);
    const auto* exception = static_cast<const LinuxException*>(platformExceptionPointers);
    if (!exception)
    {
        outMsg += "exception data unavailable\n";
        return;
    }
    const char* name = "unknown signal";
    switch (exception->signal)
    {
        case SIGSEGV: name = "SIGSEGV"; break;
        case SIGBUS: name = "SIGBUS"; break;
        case SIGILL: name = "SIGILL"; break;
        case SIGFPE: name = "SIGFPE"; break;
    }
    HardwareException::appendField(outMsg, "signal", std::format("{} ({})", exception->signal, name));
    HardwareException::appendField(outMsg, "signal code", std::format("{}", exception->signalCode));
    HardwareException::appendField(outMsg, "instruction", std::format("0x{:016X}", exception->instructionAddress));
    HardwareException::appendField(outMsg, "fault address", std::format("0x{:016X}", exception->faultAddress));
}

void Os::appendHostCpuContext(Utf8& outMsg, const void* platformExceptionPointers)
{
    const auto* exception = static_cast<const LinuxException*>(platformExceptionPointers);
    if (!exception)
    {
        outMsg += "register data unavailable\n";
        return;
    }
    constexpr std::array<const char*, 17> K_NAMES = {"rax", "rdx", "rcx", "rbx", "rsi", "rdi", "rbp", "rsp", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip"};
    for (size_t i = 0; i < K_NAMES.size(); ++i)
        HardwareException::appendField(outMsg, K_NAMES[i], std::format("0x{:016X}", exception->registers[i]));
}

void Os::appendHostHandlerStack(Utf8& outMsg, const void* platformExceptionPointers, const TaskContext* ctx)
{
    const auto* exception = static_cast<const LinuxException*>(platformExceptionPointers);
    if (!exception || !exception->frameCount)
    {
        outMsg += "fault stack unavailable\n";
        return;
    }
    for (size_t i = 0; i < std::min<size_t>(exception->frameCount, exception->frames.size()); ++i)
    {
        const uintptr_t address = exception->frames[i];
        outMsg += std::format("#{:02} 0x{:016X}", i, address);
        ResolvedAddress resolved;
        if (resolveAddress(resolved, address, ctx))
        {
            outMsg += std::format(" {}", resolved.moduleName);
            if (!resolved.symbolName.empty())
                outMsg += std::format("!{}", resolved.symbolName);
        }
        outMsg += "\n";
    }
}

SWC_END_NAMESPACE();
#endif
