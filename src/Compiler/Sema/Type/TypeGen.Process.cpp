#include "pch.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"
#include "Support/Core/DataSegment.h"

SWC_BEGIN_NAMESPACE();

SmallVector<TypeRef> TypeGen::computeDeps(const TypeManager& tm, const TaskContext& ctx, const TypeInfo& type, LayoutKind kind) const
{
    SmallVector<TypeRef> deps;

    switch (kind)
    {
        case LayoutKind::Pointer:
        case LayoutKind::Slice:
            deps.push_back(type.payloadTypeRef());
            break;

        case LayoutKind::Array:
        {
            const TypeRef elemTypeRef = type.payloadArrayElemTypeRef();
            deps.push_back(elemTypeRef);

            const TypeRef finalTypeRef = tm.get(elemTypeRef).unwrap(ctx, elemTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
            if (finalTypeRef != elemTypeRef)
                deps.push_back(finalTypeRef);
            break;
        }

        case LayoutKind::Alias:
            deps.push_back(type.payloadTypeRef());
            break;

        case LayoutKind::TypedVariadic:
            deps.push_back(type.payloadTypeRef());
            break;

        case LayoutKind::Struct:
        {
            for (const SymbolVariable* field : type.payloadSymStruct().fields())
            {
                if (!field)
                    continue;
                deps.push_back(field->typeRef());
            }
            break;
        }

        case LayoutKind::Func:
        {
            const SymbolFunction& symFunc = type.payloadSymFunction();
            if (symFunc.returnTypeRef().isValid())
            {
                const TypeRef returnTypeRef = symFunc.returnTypeRef();
                if (!tm.get(returnTypeRef).isVoid())
                    deps.push_back(returnTypeRef);
            }

            for (const SymbolVariable* param : symFunc.parameters())
            {
                if (!param)
                    continue;
                deps.push_back(param->typeRef());
            }

            break;
        }

        default:
            break;
    }

    return deps;
}

Result TypeGen::processTypeInfo(Sema& sema, TypeGenResult& result, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenCache& cache) const
{
    TaskContext&       ctx  = sema.ctx();
    const TypeManager& tm   = ctx.typeMgr();
    const AstNode&     node = sema.node(ownerNodeRef);

    // Non-recursive (explicit stack) type-info generation.
    //
    // We need to emit one runtime 'TypeInfo*' payload per type, and then "wire" all
    // the internal 'TypeRef' links to offsets in the 'DataSegment' via relocations.
    //
    // The algorithm is a DFS over type dependencies:
    // - First pass for a type: allocate payload + initialize fields that don't depend
    //   on other type infos (common init + optional struct field metadata).
    // - Collect dependencies for the type and push them.
    // - Once all deps are done: wire relocations for this type and mark it Done.
    //
    // This is intentionally iterative to avoid recursion depth issues and to allow
    // pausing/resuming if needed by the compiler pipeline.
    SmallVector<TypeRef> stack;
    stack.push_back(typeRef);

    while (!stack.empty())
    {
        // The current node in the DFS. We only pop it once it's fully processed.
        const TypeRef   key  = stack.back();
        const TypeInfo& type = tm.get(key);

        // Be sure the type is completed.
        const LayoutKind kind = layoutKindOf(type);
        if (const Symbol* sym = type.getSymbol())
            SWC_RESULT_VERIFY(sema.waitSemaCompleted(sym, node.codeRef()));

        auto it = cache.entries.find(key);
        if (it == cache.entries.end())
        {
            // The first time we see this type in the cache: allocate and initialize its
            // runtime payload, then compute its dependency list.
            TypeGenCache::Entry entry;

            // Make sure the runtime TypeInfo struct definition exists before we write
            // an instance of it into the 'DataSegment'.
            SWC_RESULT_VERIFY(rtTypeRefFor(sema, kind, entry.rtTypeRef, node.codeRef()));

            // Allocate the concrete runtime payload (TypeInfoStruct/TypeInfoPtr/...) in
            // the target storage and remember its offset.
            auto [offset, rtBase] = allocateTypeInfoPayload(storage, kind);
            entry.offset          = offset;
            initTypeInfoPayload(sema, storage, *rtBase, offset, kind, type, entry);

            // Compute direct dependencies required to wire this payload.
            entry.deps = computeDeps(tm, ctx, type, kind);
            it         = cache.entries.emplace(key, std::move(entry)).first;
        }

        auto& entry = it->second;
        if (entry.state == TypeGenCache::State::Done)
        {
            // Fully processed: pop and continue unwinding.
            stack.pop_back();
            continue;
        }

        // Push the first unmet dependency.
        bool pushedDep = false;
        for (const TypeRef depKey : entry.deps)
        {
            if (depKey == key)
                continue;

            const auto depIt = cache.entries.find(depKey);
            if (depIt != cache.entries.end())
            {
                if (depIt->second.state == TypeGenCache::State::Done)
                    continue;

                // A dependency can already exist in the cache but still be in
                // 'CommonInit' if a previous pass paused (for example, waiting on
                // sema completion). In that case, we must revisit it now.
                //
                // If this dependency is already on the current DFS stack, we are in
                // a recursion cycle and keep unwinding. Relocations can still be
                // wired because payload offsets are already reserved during init.
                const bool depOnStack = std::ranges::find(stack, depKey) != stack.end();
                if (depOnStack)
                    continue;
            }

            // Depth-first: create this dependency payload before completing 'key'.
            stack.push_back(depKey);
            pushedDep = true;
            break;
        }

        if (pushedDep)
            continue;

        // All deps are Done => wire relocations, then mark Done.
        wireRelocations(sema, cache, storage, key, entry, kind);
        entry.state = TypeGenCache::State::Done;
    }

    const auto it = cache.entries.find(typeRef);
    if (it == cache.entries.end() || it->second.state != TypeGenCache::State::Done)
        return Result::Pause;

    const auto& entry = it->second;
    result.offset     = entry.offset;
    result.rtTypeRef  = entry.rtTypeRef;

    const TypeInfo& structType = tm.get(result.rtTypeRef);
    result.span                = ByteSpan{storage.ptr<std::byte>(result.offset), structType.sizeOf(ctx)};

    sema.compiler().notifyAlive();
    return Result::Continue;
}

SWC_END_NAMESPACE();
