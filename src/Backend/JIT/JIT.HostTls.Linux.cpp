#include "pch.h"
#include "Backend/JIT/JIT.h"

#if defined(__linux__) && defined(__x86_64__)
#include "Backend/Encoder/X64DwarfFrame.h"
#include "Backend/Encoder/X64TlsAccess.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::array<uint32_t, 16> K_DWARF_REGISTERS = {0, 2, 1, 3, 7, 6, 4, 5, 8, 9, 10, 11, 12, 13, 14, 15};

    void appendInstruction(ByteArray& code, std::initializer_list<uint8_t> bytes)
    {
        code.append(std::as_bytes(std::span(bytes.begin(), bytes.size())));
    }

    uint32_t savedRegisterOffset(uint32_t reg)
    {
        SWC_ASSERT(reg < 16 && reg != 4);
        return (14 - (reg < 4 ? reg : reg - 1)) * 8;
    }

    void transferVector(ByteArray& code, uint32_t reg, bool load)
    {
        // movdqu xmmN, [rbp - 256 + N*16], or its store form. Use RBP so the
        // address stays fixed when the call stack is rounded down for System V.
        code.pushBack(std::byte{0xf3});
        if (reg >= 8)
            code.pushBack(std::byte{0x44});
        appendInstruction(code, {0x0f, static_cast<uint8_t>(load ? 0x6f : 0x7f), static_cast<uint8_t>(0x85 | ((reg & 7) << 3))});
        code.appendLe32(static_cast<uint32_t>(-256 + static_cast<int32_t>(reg * 16)));
    }

    void buildTlsReadAdapter(ByteArray& code, ByteArray& unwindInfo, const X64TlsAccess& access)
    {
        // The replaced instruction is a read, not an ABI call: every register and
        // EFLAGS except the destination must survive. The backend's vector lanes
        // are 128 bits. A frame pointer keeps the unwind rules valid for both a
        // frameless leaf's stack and a regular caller's stack alignment.
        X64DwarfFrame frame;
        frame.reset();
        uint32_t cfaOffset = 8;
        appendInstruction(code, {0x9c}); // pushfq
        frame.advance(static_cast<uint32_t>(code.size()));
        frame.defineCfa(7, cfaOffset += 8);
        for (uint32_t reg = 0; reg < 16; ++reg)
        {
            if (reg == 4)
                continue;
            if (reg >= 8)
                code.pushBack(std::byte{0x41});
            code.pushBack(static_cast<std::byte>(0x50 | (reg & 7)));
            frame.advance(static_cast<uint32_t>(code.size()));
            frame.defineCfa(7, cfaOffset += 8);
            frame.saveRegister(K_DWARF_REGISTERS[reg], -static_cast<int32_t>(cfaOffset));
        }
        appendInstruction(code, {0x48, 0x89, 0xe5}); // mov rbp, rsp
        frame.advance(static_cast<uint32_t>(code.size()));
        frame.defineCfa(6, cfaOffset);
        appendInstruction(code, {0x48, 0x81, 0xec, 0, 1, 0, 0}); // sub rsp, 256
        for (uint32_t reg = 0; reg < 16; ++reg)
        {
            transferVector(code, reg, false);
            frame.advance(static_cast<uint32_t>(code.size()));
            frame.saveRegister(17 + reg, -static_cast<int32_t>(cfaOffset + 256 - reg * 16));
        }
        appendInstruction(code, {0x48, 0x83, 0xe4, 0xf0}); // and rsp, -16
        appendInstruction(code, {0x48, 0x8b, 0xbd}); // mov rdi, saved slot+1
        code.appendLe32(savedRegisterOffset(access.slot));
        appendInstruction(code, {0x48, 0x83, 0xef, 1}); // sub rdi, 1
        appendInstruction(code, {0x48, 0xb8}); // mov rax, host TLS getter
        code.appendLe64(reinterpret_cast<uint64_t>(&Os::tlsGetValue));
        appendInstruction(code, {0xff, 0xd0}); // call rax
        appendInstruction(code, {0x48, 0x89, 0x85}); // replace the saved destination
        code.appendLe32(savedRegisterOffset(access.destination));
        for (uint32_t reg = 0; reg < 16; ++reg)
        {
            transferVector(code, reg, true);
            frame.advance(static_cast<uint32_t>(code.size()));
            frame.restoreRegister(17 + reg);
        }
        appendInstruction(code, {0x48, 0x89, 0xec}); // mov rsp, rbp
        frame.advance(static_cast<uint32_t>(code.size()));
        frame.defineCfa(7, cfaOffset);
        for (uint32_t index = 16; index != 0; --index)
        {
            const uint32_t reg = index - 1;
            if (reg == 4)
                continue;
            if (reg >= 8)
                code.pushBack(std::byte{0x41});
            code.pushBack(static_cast<std::byte>(0x58 | (reg & 7)));
            frame.advance(static_cast<uint32_t>(code.size()));
            frame.defineCfa(7, cfaOffset -= 8);
            frame.restoreRegister(K_DWARF_REGISTERS[reg]);
        }
        appendInstruction(code, {0x9d}); // popfq
        frame.advance(static_cast<uint32_t>(code.size()));
        frame.defineCfa(7, cfaOffset -= 8);
        appendInstruction(code, {0xc3});
        SWC_ASSERT(cfaOffset == 8);
        frame.build(unwindInfo, static_cast<uint32_t>(code.size()));
    }
}

void* JIT::hostTlsReadAdapter(const X64TlsAccess& access)
{
    struct Adapter
    {
        uint32_t destination;
        uint32_t slot;
        JITMemory memory;
    };
    struct Cache
    {
        std::mutex mutex;
        JITMemoryManager manager;
        std::vector<Adapter> entries;
    };
    static Cache cache;
    const std::scoped_lock lock(cache.mutex);
    for (const Adapter& adapter : cache.entries)
        if (adapter.destination == access.destination && adapter.slot == access.slot)
            return adapter.memory.entryPoint();

    ByteArray code, unwindInfo;
    buildTlsReadAdapter(code, unwindInfo, access);
    JITMemory memory;
    prepare(cache.manager, memory, code, unwindInfo, {});
    finalize(memory);
    void* entry = memory.entryPoint();
    cache.entries.push_back({access.destination, access.slot, std::move(memory)});
    return entry;
}

SWC_END_NAMESPACE();
#endif
