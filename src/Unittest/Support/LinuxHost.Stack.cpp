#include "pch.h"
#include "Support/Os/Os.h"
#include "Unittest/Support/LinuxHostTests.h"

namespace swc::LinuxHostTests
{
    // Keep actual frames and an exported C++ symbol in optimized builds as well.
    __attribute__((noinline)) uint32_t captureNestedStack(const std::span<uintptr_t> frames, const uint32_t depth, const uint32_t skip)
    {
        const uint32_t count = depth ? captureNestedStack(frames, depth - 1, skip) : Os::captureCallStack(frames, skip);
        asm volatile("" : : "r"(count) : "memory");
        return count;
    }

    void testCallStacks()
    {
        const uint32_t expected = 0x12345678;
        uint32_t value = 0;
        const auto destination = std::as_writable_bytes(std::span{&value, 1});
        require(Os::tryReadMemory(destination, &expected) && value == expected, "diagnostic memory read changed the value");
        require(Os::tryReadMemory({}, nullptr), "empty diagnostic read failed");
        require(!Os::tryReadMemory(destination, nullptr) && !Os::tryReadMemory(destination, reinterpret_cast<void*>(1)), "invalid diagnostic address was readable");
        void* released = Os::allocProximityMemory(Os::memoryPageSize());
        require(released != nullptr, "cannot allocate diagnostic-read fixture");
        Os::freeProximityMemory(released, Os::memoryPageSize());
        require(!Os::tryReadMemory(destination, released), "diagnostic read ignored page protection");

        std::array<uintptr_t, 70> frames{};
        require(Os::captureCallStack({}) == 0, "empty stack destination was not accepted");
        const uint32_t count = captureNestedStack(frames, 80, 0);
        require(count == 64 && frames[64] == 0, "stack capture did not preserve its frame cap");
        Os::ResolvedAddress resolved;
        require(Os::resolveAddress(resolved, frames[0]), "cannot resolve the first captured frame");
        require(!resolved.moduleName.empty() && resolved.symbolName.contains("captureNestedStack"), "stack starts outside the caller");
        require(resolved.symbolName.contains("swc::LinuxHostTests::"), "C++ frame symbol was not demangled");
        require(resolved.sourceLocation.empty(), "ELF symbol lookup invented a source location");

        frames.fill(0);
        const uint32_t skipped = captureNestedStack(frames, 80, 80);
        require(skipped > 0 && skipped < 20, "stack skip was limited to the output frame capacity");
        require(captureNestedStack(frames, 1, UINT32_MAX) == 0, "oversized stack skip overflowed");
        frames.fill(0);
        require(captureNestedStack(std::span(frames).first(1), 1, 0) == 1 && frames[1] == 0, "stack capture overran a small destination");

        require(!Os::resolveAddress(resolved, 0) && resolved.moduleName.empty() && resolved.symbolName.empty() && resolved.sourceLocation.empty(), "failed resolution retained an earlier frame");
        require(!Os::resolveAddress(resolved, 1), "invalid address resolved to a module");
        void* module = nullptr;
        void* symbol = nullptr;
        require(Os::loadExternalModule(module, "libc.so.6") && Os::getExternalSymbolAddress(symbol, module, "getpid"), "cannot load an external stack symbol");
        require(Os::resolveAddress(resolved, reinterpret_cast<uintptr_t>(symbol)) && resolved.moduleName.contains("libc.so"), "external symbol did not resolve to its own image");
    }
}
