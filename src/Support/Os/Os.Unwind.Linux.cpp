#include "pch.h"
#include "Backend/Encoder/DwarfFrame.x64.h"
#include "Backend/JIT/JITMemory.h"
#include "Support/Os/Os.h"
#include "Support/Os/Os.Exception.Linux.h"

#ifdef __linux__
extern "C" void __register_frame(const void* frame);
extern "C" void __deregister_frame(const void* frame);

SWC_BEGIN_NAMESPACE();

namespace
{
    struct RegisteredFrame
    {
        ByteArray frame;
        uintptr_t start = 0;
        uintptr_t end = 0;
        std::atomic<RegisteredFrame*> next = nullptr;
        RegisteredFrame* previous = nullptr; // Only registration writers use this link.
    };

    std::mutex frameMutex;
    std::atomic<RegisteredFrame*> firstFrame = nullptr;
    std::atomic<uint32_t> frameReaders = 0;
    static_assert(std::atomic<RegisteredFrame*>::is_always_lock_free && std::atomic<uint32_t>::is_always_lock_free);
}

bool Os::isRegisteredJitCode(const uintptr_t address)
{
    // The signal path cannot take a mutex: it may interrupt a registration writer.
    // Sequential consistency orders entering readers against unlink and reclamation.
    // Readers never retain a node after leaving this bounded traversal.
    frameReaders.fetch_add(1);
    bool found = false;
    for (const RegisteredFrame* node = firstFrame.load(); node; node = node->next.load())
    {
        if (address >= node->start && address < node->end)
        {
            found = true;
            break;
        }
    }
    frameReaders.fetch_sub(1);
    return found;
}

bool Os::addHostJitFunctionTable(JITMemory& executableMemory)
{
    if (executableMemory.hostRuntimeFunction_)
        return true;
    if (!executableMemory.hasUnwindInfo())
        return true;
    if (!executableMemory.ptr_ || executableMemory.unwindInfoOffset_ < executableMemory.size_ ||
        executableMemory.unwindInfoOffset_ > executableMemory.allocationSize_ ||
        executableMemory.unwindInfoSize_ > executableMemory.allocationSize_ - executableMemory.unwindInfoOffset_)
        return false;

    // Executable storage may already be RX. Keep relocated, naturally aligned
    // metadata separately so registration never opens code pages for writing.
    const auto* source = static_cast<const std::byte*>(executableMemory.ptr_) + executableMemory.unwindInfoOffset_;
    auto node = std::make_unique<RegisteredFrame>();
    node->frame.assign(source, source + executableMemory.unwindInfoSize_);
    node->start = reinterpret_cast<uintptr_t>(executableMemory.ptr_);
    node->end = node->start + executableMemory.size_;
    if (!X64DwarfFrame::relocate(node->frame, node->start, executableMemory.size_))
        return false;
    {
        const std::scoped_lock lock(frameMutex);
        __register_frame(node->frame.data());
        RegisteredFrame* first = firstFrame.load();
        node->next.store(first);
        if (first)
            first->previous = node.get();
        firstFrame.store(node.get());
    }
    executableMemory.hostRuntimeFunction_ = node.release();
    return true;
}

void Os::removeHostJitFunctionTable(JITMemory& executableMemory)
{
    auto* node = static_cast<RegisteredFrame*>(executableMemory.hostRuntimeFunction_);
    if (!node)
        return;
    {
        const std::scoped_lock lock(frameMutex);
        RegisteredFrame* next = node->next.load();
        if (node->previous)
            node->previous->next.store(next);
        else
            firstFrame.store(next);
        if (next)
            next->previous = node->previous;
    }
    while (frameReaders.load())
        std::this_thread::yield();
    __deregister_frame(node->frame.data());
    delete node;
    executableMemory.hostRuntimeFunction_ = nullptr;
}

SWC_END_NAMESPACE();
#endif
