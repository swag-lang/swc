#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Module.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

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

// Re-cloning an analyzed identifier must read its current AST's payload even
// though both clones retain the token location of the original source file.
SWC_TEST_BEGIN(NodePayload_RecloneReadsOwningAstWithBorrowedSourceLocation)
{
    SourceFile& original = Unittest::addTestSource(ctx, "NodePayload", "RecloneOriginal", "kept decoy");
    SourceFile& middle   = Unittest::addTestSource(ctx, "NodePayload", "RecloneMiddle", "");
    SourceFile& target   = Unittest::addTestSource(ctx, "NodePayload", "RecloneTarget", "");
    Lexer       lexer;
    lexer.tokenize(ctx, original.ast().srcView(), LexerFlagsE::Default);
    if (original.ast().srcView().mustSkip())
        return Result::Error;

    constexpr SymbolFlags namespaceFlags  = SymbolFlagsE::Declared | SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted;
    auto*                 module          = Symbol::make<SymbolModule>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    const IdentifierRef   namespaceId     = ctx.idMgr().addIdentifierOwned("NodePayloadReclone");
    auto*                 moduleNamespace = Symbol::make<SymbolNamespace>(ctx, nullptr, TokenRef::invalid(), namespaceId, namespaceFlags);
    module->addSingleSymbol(ctx, moduleNamespace);
    for (SourceFile* file : {&original, &middle, &target})
    {
        auto [rootRef, root] = file->ast().makeNode<AstNodeId::File>(TokenRef::invalid());
        SWC_UNUSED(root);
        file->ast().setRoot(rootRef);
        file->setModuleNamespace(*moduleNamespace);
        file->setFileNamespace(*moduleNamespace);
    }

    Sema originalSema(ctx, original.nodePayloadContext(), false);
    Sema middleSema(ctx, middle.nodePayloadContext(), false);
    Sema targetSema(ctx, target.nodePayloadContext(), false);
    auto [keptRef, keptNode]   = original.ast().makeNode<AstNodeId::Identifier>(TokenRef{0});
    auto [decoyRef, decoyNode] = original.ast().makeNode<AstNodeId::Identifier>(TokenRef{1});
    SymbolVariable kept(nullptr, TokenRef{0}, ctx.idMgr().addIdentifierOwned("kept"), {});
    SymbolVariable decoy(nullptr, TokenRef{1}, ctx.idMgr().addIdentifierOwned("decoy"), {});
    kept.setTypeRef(ctx.typeMgr().typeU64());
    decoy.setTypeRef(ctx.typeMgr().typeU64());
    originalSema.setSymbol(keptRef, &kept);
    originalSema.setSymbol(decoyRef, &decoy);

    // Make the middle clone's AST-local index name the decoy in the original
    // AST, so reading the borrowed source file yields a valid but wrong symbol.
    middle.ast().makeNode<AstNodeId::Identifier>(TokenRef::invalid());
    const SemaClone::CloneContext firstContext({}, {}, false, &original.ast());
    const AstNodeRef              middleRef = SemaClone::cloneAst(middleSema, keptRef, firstContext);
    if (middleRef.get() != decoyRef.get() || middleSema.viewSymbol(middleRef).sym() != &kept)
        return Result::Error;
    if (middle.ast().node(middleRef).codeRef() != keptNode->codeRef())
        return Result::Error;

    const SemaClone::CloneContext secondContext({}, {}, false, &middle.ast());
    const AstNodeRef              targetRef = SemaClone::cloneAst(targetSema, middleRef, secondContext);
    if (targetSema.viewSymbol(targetRef).sym() != &kept)
        return Result::Error;
    if (target.ast().node(targetRef).codeRef() != keptNode->codeRef())
        return Result::Error;
    if (originalSema.viewSymbol(decoyRef).sym() != &decoy)
        return Result::Error;
    SWC_UNUSED(decoyNode);
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

// A call argument that folds to a constant aggregate keeps one runtime storage. The cast that
// folds detaches the storage from the argument node, and sema runs the call again while it
// waits for the callee declared further down: every rerun reattached a new storage and
// reserved another frame slot, so the frame grew with the number of reruns and depended on
// scheduling.
SWC_TEST_BEGIN(NodePayload_FoldedAggregateArgumentKeepsOneRuntimeStorage)
{
    static constexpr std::string_view SOURCE     = R"(#[Swag.NoInline]
func foldedLocationCaller()->u32 => lateLocationLine(#curlocation)

#[Swag.NoInline]
func lateLocationLine(loc: Swag.SourceCodeLocation)->u32 => loc.lineStart + 1

#test
{
    Swag.assert(foldedLocationCaller() != 0)
}
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("NodePayload", "FoldedAggregateArgumentKeepsOneRuntimeStorage");

    CommandLine cmdLine;
    cmdLine.command  = CommandKind::Test;
    cmdLine.buildCfg = "release";
    cmdLine.name     = "compiler_test_folded_argument_storage";
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    const TaskContext     compilerCtx(compiler);
    const SymbolFunction* caller = nullptr;
    for (const SymbolFunction* function : compiler.nativeCodeSegment())
    {
        if (function && function->name(compilerCtx) == "foldedLocationCaller")
            caller = function;
    }

    if (!caller)
        return Result::Error;

    uint32_t argumentStorages = 0;
    for (const SymbolVariable* local : caller->localVariables())
    {
        if (local && local->name(compilerCtx).starts_with("__call_arg_ref_storage"))
            argumentStorages++;
    }

    if (argumentStorages != 1)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
