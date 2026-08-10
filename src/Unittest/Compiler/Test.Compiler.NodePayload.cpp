#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Sema/Core/NodePayload.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class NodePayloadTestAccess : public NodePayload
    {
    public:
        static void addValueFlag(AstNode& node) { addPayloadFlags(node, NodePayloadFlags::Value); }
        static void setTypeKind(AstNode& node) { setPayloadKind(node, NodePayloadKind::TypeRef); }
    };
}

SWC_TEST_BEGIN(NodePayload_ConcurrentUpdatesPreserveDisjointState)
{
    static constexpr uint32_t ITERATION_COUNT = 10'000;

    AstNode          node;
    std::barrier     rendezvous(2);
    std::atomic_bool valid = true;

    std::thread flagWriter([&] {
        for (uint32_t i = 0; i < ITERATION_COUNT; ++i)
        {
            node.storePayloadState(0, std::memory_order_relaxed);
            rendezvous.arrive_and_wait();
            NodePayloadTestAccess::addValueFlag(node);
            rendezvous.arrive_and_wait();

            const uint16_t bits = node.payloadBits();
            if ((bits & static_cast<uint16_t>(NodePayloadFlags::Value)) == 0 ||
                (bits & NODE_PAYLOAD_KIND_MASK) != static_cast<uint16_t>(NodePayloadKind::TypeRef))
                valid.store(false, std::memory_order_relaxed);
        }
    });

    for (uint32_t i = 0; i < ITERATION_COUNT; ++i)
    {
        rendezvous.arrive_and_wait();
        NodePayloadTestAccess::setTypeKind(node);
        rendezvous.arrive_and_wait();
    }

    flagWriter.join();
    if (!valid.load(std::memory_order_relaxed))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
