#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class NodePayloadTestAccess : public NodePayload
    {
    public:
        using NodePayload::addPayloadFlags;
        using NodePayload::ast;
        using NodePayload::setSymbolList;

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

SWC_TEST_BEGIN(NodePayload_MutableAndConstSymbolListsPreserveFlagsAndOrder)
{
    SourceView            sourceView(SourceViewRef{0}, nullptr);
    NodePayloadTestAccess payload;
    payload.ast().setSourceView(sourceView);
    SymbolVariable variable(nullptr, TokenRef::invalid(), IdentifierRef{1}, {});
    SymbolFunction function(nullptr, TokenRef::invalid(), IdentifierRef{2}, {});
    SymbolAlias    alias(nullptr, TokenRef::invalid(), IdentifierRef{3}, {});
    SymbolAlias    unresolvedAlias(nullptr, TokenRef::invalid(), IdentifierRef{4}, {});
    alias.setAliasedSymbol(&variable);

    constexpr uint16_t valueFlag  = static_cast<uint16_t>(NodePayloadFlags::Value);
    constexpr uint16_t lvalueFlag = static_cast<uint16_t>(NodePayloadFlags::LValue);
    constexpr uint16_t markerFlag = static_cast<uint16_t>(NodePayloadFlags::ConstAssignBinding);
    struct TestCase
    {
        std::vector<Symbol*> symbols;
        uint16_t             flags;
    };
    const std::array cases = {
        TestCase{{}, valueFlag | lvalueFlag},
        TestCase{{&variable, &alias}, valueFlag | lvalueFlag},
        TestCase{{&variable, &function, &alias}, lvalueFlag},
        TestCase{{&unresolvedAlias, &variable}, 0},
        TestCase{std::vector<Symbol*>(40, &alias), valueFlag | lvalueFlag},
    };
    for (const TestCase& test : cases)
    {
        const auto [mutableRef, mutableNode] = payload.ast().makeNode<AstNodeId::Identifier>(TokenRef::invalid());
        const auto [constRef, constNode]     = payload.ast().makeNode<AstNodeId::Identifier>(TokenRef::invalid());
        NodePayloadTestAccess::addPayloadFlags(*mutableNode, NodePayloadFlags::ConstAssignBinding);
        NodePayloadTestAccess::addPayloadFlags(*constNode, NodePayloadFlags::ConstAssignBinding);
        {
            auto                       mutableSymbols = test.symbols;
            std::vector<const Symbol*> constSymbols(test.symbols.begin(), test.symbols.end());
            payload.setSymbolList(mutableRef, std::span<Symbol*>(mutableSymbols));
            payload.setSymbolList(constRef, std::span<const Symbol*>(constSymbols));
            std::ranges::fill(mutableSymbols, nullptr);
            std::ranges::fill(constSymbols, nullptr);
        }
        if (!std::ranges::equal(payload.resolveSymbols(mutableRef).symbols, test.symbols))
            return Result::Error;
        if (!std::ranges::equal(payload.resolveSymbols(constRef).symbols, test.symbols))
            return Result::Error;
        if ((mutableNode->payloadBits() & NODE_PAYLOAD_FLAGS_MASK) != (test.flags | markerFlag))
            return Result::Error;
        if ((constNode->payloadBits() & NODE_PAYLOAD_FLAGS_MASK) != (test.flags | markerFlag))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
