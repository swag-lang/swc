#include "pch.h"
#include "Compiler/Sema/Helpers/SemaBodyCache.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerCacheStore.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/ByteArray.h"
#include "Support/Core/ByteView.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Math/Sha256.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr size_t K_CHECKSUM_SIZE = 32;
    constexpr size_t K_RECORD_SIZE   = 2 * sizeof(uint32_t);

    std::array<uint8_t, K_CHECKSUM_SIZE> bodyArchiveChecksum(std::span<const std::byte> payload, const Utf8& key)
    {
        return sha256Parts({payload, std::as_bytes(std::span{key.view()})});
    }

    void appendText(ByteArray& bytes, std::string_view text)
    {
        bytes.appendLe64(text.size());
        bytes.append(text);
    }

    bool hasBodyCompilerSyntax(const Ast& ast, AstNodeRef body)
    {
        SmallVector<AstNodeRef> pending;
        pending.push_back(body);
        while (!pending.empty())
        {
            const AstNodeRef ref = pending.back();
            pending.pop_back();
            if (ref.isInvalid())
                continue;

            const AstNode& node = ast.node(ref);
            if (Ast::nodeIdName(node.id()).starts_with("Compiler") ||
                node.is(AstNodeId::UsingDecl) || node.is(AstNodeId::UsingNamespaceStmt) ||
                node.is(AstNodeId::NamespaceDecl) || node.is(AstNodeId::AliasDecl) ||
                node.is(AstNodeId::Impl) || node.is(AstNodeId::AttrDecl) ||
                node.is(AstNodeId::FunctionDecl) || node.is(AstNodeId::FunctionExpr) ||
                node.is(AstNodeId::ClosureExpr) || node.is(AstNodeId::StructDecl) ||
                node.is(AstNodeId::EnumDecl) || node.is(AstNodeId::InterfaceDecl))
                return true;
            node.collectChildrenFromAst(pending, ast);
        }
        return false;
    }
}

SemaBodyCache::SemaBodyCache(CompilerInstance& compiler, std::span<SourceFile* const> parsedFiles) :
    compiler_(compiler)
{
    struct Input
    {
        const SourceFile* file;
        std::array<uint8_t, 32> digest;
    };

    std::vector<Input> inputs;
    inputs.reserve(parsedFiles.size());
    for (const auto* file : parsedFiles)
    {
        if (!file->isRuntime() && !file->sourceOwner())
            continue;

        const auto bytes = std::as_bytes(std::span{file->ast().srcView().stringView()});
        inputs.push_back({file, sha256(bytes)});
        if (!file->isRuntime())
            groups_.try_emplace(file->sourceOwner());
        else
            hasRuntimeGroup_ = true;
    }

    std::ranges::sort(inputs, {}, [](const Input& input) {
        return std::pair{input.file->sourceOwner(), input.file->genericPathString().view()};
    });

    TaskContext ctx(compiler);
    const auto& command = compiler.cmdLine();
    ByteArray initialConfig;
    compiler.appendBuildConfigCacheIdentity(initialConfig);
    const auto configDigest = sha256(initialConfig.span());

    if (hasRuntimeGroup_)
    {
        ByteArray identity;
        identity.append("checked dormant runtime bodies v1");
        identity.appendLe32(static_cast<uint32_t>(command.targetOs));
        identity.appendLe32(static_cast<uint32_t>(command.targetArch));
        identity.appendLe32(static_cast<uint32_t>(command.command));
        appendText(identity, command.targetCpu.view());
        appendText(identity, command.buildCfg.view());
        identity.append(std::as_bytes(std::span{configDigest}));
        command.warningPolicy.appendCacheIdentity(identity);
        compiler.warningPolicy().appendCacheIdentity(identity);
        identity.appendLe64(command.tags.size());
        for (const auto& tag : command.tags)
            appendText(identity, tag.view());

        for (const auto& input : inputs)
        {
            const auto& file = *input.file;
            if (!file.isRuntime())
                continue;

            runtimeGroup_.fileIndices.emplace(file.ref().get(), static_cast<uint32_t>(runtimeGroup_.files.size()));
            runtimeGroup_.files.push_back(&file);
            identity.appendLe32(file.flags().get());
            appendText(identity, file.genericPathString().view());
            if (file.moduleNamespace())
                appendText(identity, file.moduleNamespace()->getFullScopedName(ctx).view());
            else
                appendText(identity, {});
            identity.append(std::as_bytes(std::span{input.digest}));
        }

        runtimeGroup_.config       = compiler.buildCfg();
        runtimeGroup_.configDigest = configDigest;
        runtimeGroup_.key = Utf8Helper::toLowerHex(sha256Parts({identity.span(), std::as_bytes(std::span{configDigest})}));
        if (!command.rebuild && !compiler.jitHasUntrackedEffects())
            runtimeGroup_.loaded = load(runtimeGroup_);
    }

    for (auto& [owner, group] : groups_)
    {
        ByteArray identity;
        identity.append("checked dormant ordinary bodies v1");
        identity.appendLe32(static_cast<uint32_t>(command.targetOs));
        identity.appendLe32(static_cast<uint32_t>(command.targetArch));
        identity.appendLe32(static_cast<uint32_t>(command.command));
        appendText(identity, command.targetCpu.view());
        appendText(identity, command.buildCfg.view());
        identity.append(std::as_bytes(std::span{configDigest}));
        command.warningPolicy.appendCacheIdentity(identity);
        compiler.warningPolicy().appendCacheIdentity(identity);
        identity.appendLe64(command.tags.size());
        for (const auto& tag : command.tags)
            appendText(identity, tag.view());

        // Keep the order and visibility of the groups whose declarations can be
        // seen here. Unrelated groups or application edits do not enter this key.
        SmallVector<uint32_t> visibleOwners;
        for (const auto& [visible, unused] : groups_)
        {
            if (compiler.canSeeSourceOwner(owner, visible))
                visibleOwners.push_back(visible);
        }

        identity.appendLe64(visibleOwners.size());
        for (const uint32_t from : visibleOwners)
        {
            for (const uint32_t target : visibleOwners)
                identity.appendLe32(compiler.canSeeSourceOwner(from, target));
        }

        for (const auto& input : inputs)
        {
            const auto& file = *input.file;
            if (!file.isRuntime() && !compiler.canSeeSourceOwner(owner, file.sourceOwner()))
                continue;

            if (!file.isRuntime() && file.sourceOwner() == owner)
            {
                group.fileIndices.emplace(file.ref().get(), static_cast<uint32_t>(group.files.size()));
                group.files.push_back(&file);
            }

            const auto groupIndex = file.isRuntime() ? visibleOwners.end() : std::ranges::find(visibleOwners, file.sourceOwner());
            identity.appendLe32(static_cast<uint32_t>(groupIndex - visibleOwners.begin()));
            identity.appendLe32(file.flags().get());
            appendText(identity, file.genericPathString().view());
            if (file.moduleNamespace())
                appendText(identity, file.moduleNamespace()->getFullScopedName(ctx).view());
            else
                appendText(identity, {});
            identity.append(std::as_bytes(std::span{input.digest}));
        }

        group.key = Utf8Helper::toLowerHex(sha256(identity.span()));
    }
}

bool SemaBodyCache::load(Group& group)
{
    const auto record = CompilerCacheStore::get().read(group.key);
    if (!record || record.bytes.size() <= K_CHECKSUM_SIZE)
        return false;

    const ByteView payload(record.bytes.span().first(record.bytes.size() - K_CHECKSUM_SIZE));
    if (payload.size() % K_RECORD_SIZE)
        return false;
    const auto checksum = bodyArchiveChecksum(payload.span(), group.key);
    if (std::memcmp(checksum.data(), record.bytes.data() + payload.size(), K_CHECKSUM_SIZE))
        return false;

    std::vector<std::unordered_set<uint32_t>> deferred(group.files.size());
    for (size_t offset = 0; offset < payload.size(); offset += K_RECORD_SIZE)
    {
        const uint32_t index = payload.readLe32(offset);
        const uint32_t token = payload.readLe32(offset + sizeof(index));
        if (index >= group.files.size() || token >= group.files[index]->ast().srcView().numTokens())
            return false;
        deferred[index].insert(token);
    }

    group.deferred = std::move(deferred);
    return true;
}

bool SemaBodyCache::hasVisibleInput(uint32_t owner) const
{
    return runtimeInputRead_ || std::ranges::any_of(groups_, [&](const auto& entry) {
        return entry.second.inputRead && compiler_.canSeeSourceOwner(owner, entry.first);
    });
}

void SemaBodyCache::beginOwner(uint32_t sourceOwner)
{
    // A source-owner barrier has drained its semantic jobs and compiler callbacks.
    const std::unique_lock lock(mutex_);
    ByteArray config;
    compiler_.appendBuildConfigCacheIdentity(config);
    const auto digest = sha256(config.span());

    if (const auto previous = groups_.find(activeOwner_); previous != groups_.end())
    {
        previous->second.checked = previous->second.configDigest == digest &&
                                   !compiler_.jitHasUntrackedEffects() && !hasVisibleInput(activeOwner_);
    }
    if (hasRuntimeGroup_ && !runtimeGroup_.checked)
    {
        runtimeGroup_.checked = runtimeGroup_.configDigest == digest &&
                                !compiler_.jitHasUntrackedEffects() && !runtimeInputRead_;
    }
    activeOwner_ = sourceOwner;
    application_ = sourceOwner == 0;

    const auto group = groups_.find(sourceOwner);
    if (group == groups_.end())
        return;

    // Compiler code can see the current module's configuration. Earlier
    // source groups can also have changed it since the prelude ran.
    auto& data        = group->second;
    data.config       = compiler_.buildCfg();
    data.configDigest = digest;
    data.key          = Utf8Helper::toLowerHex(sha256Parts({std::as_bytes(std::span{data.key.view()}), std::as_bytes(std::span{digest})}));
    if (!compiler_.cmdLine().rebuild && !compiler_.jitHasUntrackedEffects() && !hasVisibleInput(sourceOwner))
        data.loaded = load(data);
}

void SemaBodyCache::recordInput()
{
    const std::unique_lock lock(mutex_);
    if (const auto group = groups_.find(activeOwner_); group != groups_.end())
        group->second.inputRead = true;
    else if (!application_)
        runtimeInputRead_ = true;
}

const Runtime::BuildCfg* SemaBodyCache::deferredBuildConfig(const SourceFile& file, TokenRef token) const
{
    const std::shared_lock lock(mutex_);
    if (compiler_.jitHasUntrackedEffects())
        return nullptr;

    const Group* group = nullptr;
    if (file.isRuntime())
    {
        if (!hasRuntimeGroup_ || !runtimeGroup_.loaded || runtimeInputRead_)
            return nullptr;
        group = &runtimeGroup_;
    }
    else
    {
        if (activeOwner_ != file.sourceOwner() || hasVisibleInput(file.sourceOwner()))
            return nullptr;
        const auto entry = groups_.find(file.sourceOwner());
        if (entry == groups_.end() || !entry->second.loaded)
            return nullptr;
        group = &entry->second;
    }

    const auto index = group->fileIndices.find(file.ref().get());
    if (index == group->fileIndices.end() || !group->deferred[index->second].contains(token.get()))
        return nullptr;
    return &group->config;
}

bool SemaBodyCache::isEligible(const SourceFile& file, const SymbolFunction& function)
{
    if ((!file.isRuntime() && !file.sourceOwner()) || file.hasFlag(FileFlagsE::CustomSrc) ||
        function.isGenericRoot() || function.isGenericInstance() ||
        function.isEmpty() || function.isForeign() || function.specOpKind() != SpecOpKind::None ||
        function.attributes().hasMacroOrMixin() || !function.ownerSymMap())
        return false;

    const auto* owner = function.ownerSymMap();
    if (const auto* impl = owner->safeCast<SymbolImpl>())
    {
        const auto* structure = impl->isForStruct() ? impl->symStruct() : nullptr;
        if (!structure || impl->isForInterface() || impl->symInterface() ||
            structure->isGenericRoot() || structure->isGenericInstance())
            return false;
    }
    else if (!owner->isNamespace() || function.isMethod())
        return false;

    const auto* decl = function.declAs<AstFunctionDecl>();
    const auto  ref  = function.declNodeRef();
    return decl && decl->nodeBodyRef.isValid() &&
           (!decl->hasFlag(AstFunctionFlagsE::Short) || decl->nodeReturnTypeRef.isValid()) &&
           ref.isValid() && !file.ast().isAdditionalNode(ref);
}

void SemaBodyCache::recordEffect(Sema& sema)
{
    auto* cache = sema.compiler().semaBodyCache();
    const auto* function = sema.currentFunction();
    if (!cache || !function)
        return;

    const auto* file = sema.compiler().declaringSourceFile(*function);
    if (!file || !isEligible(*file, *function))
        return;

    const std::unique_lock lock(cache->mutex_);
    cache->effects_.insert(function);
}

void SemaBodyCache::publish(std::span<SymbolFunction* const> functions, const std::unordered_set<uint32_t>& messageOwners) const
{
    if (Stats::hasError() || Stats::get().numWarnings.load(std::memory_order_relaxed))
        return;

    std::map<std::pair<bool, uint32_t>, ByteArray> records;
    for (const auto* function : functions)
    {
        const auto* file = compiler_.declaringSourceFile(*function);
        if (!file || !isEligible(*file, *function) || !function->isSemaCompleted() ||
            function->isCodeGenCompleted() || function->jitEntryAddress() || effects_.contains(function))
            continue;

        const bool     isRuntime = file->isRuntime();
        const Group*   group     = nullptr;
        const uint32_t groupOwner = file->sourceOwner();
        if (isRuntime)
        {
            if (!hasRuntimeGroup_ || !runtimeGroup_.checked || runtimeGroup_.loaded)
                continue;
            group = &runtimeGroup_;
        }
        else
        {
            const auto found = groups_.find(groupOwner);
            if (found == groups_.end() || !found->second.checked || found->second.loaded)
                continue;
            group = &found->second;
        }
        // Runtime declarations are deliberately excluded from module-level compiler message
        // events. A listener in an application cannot observe whether one of these bodies was
        // checked eagerly or resumed on demand.
        if (!isRuntime && std::ranges::any_of(messageOwners, [&](uint32_t owner) {
                return !owner || compiler_.canSeeSourceOwner(groupOwner, owner);
            }))
            continue;

        const auto& decl = *function->declAs<AstFunctionDecl>();
        if (hasBodyCompilerSyntax(file->ast(), decl.nodeBodyRef))
            continue;

        const auto index = group->fileIndices.find(file->ref().get());
        if (index == group->fileIndices.end())
            continue;

        auto& payload = records[{isRuntime, groupOwner}];
        payload.appendLe32(index->second);
        payload.appendLe32(function->tokRef().get());
    }

    for (auto& [owner, payload] : records)
    {
        const auto& key = owner.first ? runtimeGroup_.key : groups_.at(owner.second).key;
        const auto checksum = bodyArchiveChecksum(payload.span(), key);
        payload.append(std::as_bytes(std::span{checksum}));
        CompilerCacheStore::get().write(key, std::move(payload));
    }
}

SWC_END_NAMESPACE();
