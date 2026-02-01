#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeGen.Internal.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"
#include "Runtime/DataSegment.h"

SWC_BEGIN_NAMESPACE();

namespace TypeGenInternal
{
    SmallVector<TypeRef> computeDeps(const TypeManager& tm, const TaskContext& ctx, const TypeInfo& type, LayoutKind kind)
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
                for (const auto* field : type.payloadSymStruct().fields())
                {
                    if (!field)
                        continue;
                    deps.push_back(field->typeRef());
                }
                break;
            }

            default:
                break;
        }

        return deps;
    }

    Result processTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGen::TypeGenResult& result, TypeGen::TypeGenCache& cache)
    {
        auto&              ctx  = sema.ctx();
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
        SmallVector<TypeRef>        stack;
        std::unordered_set<TypeRef> inStack;

        stack.push_back(typeRef);
        inStack.insert(typeRef);

        while (!stack.empty())
        {
            // The current node in the DFS. We only pop it once it's fully processed.
            const TypeRef   key  = stack.back();
            const TypeInfo& type = tm.get(key);

            // Be sure the type is completed.
            const LayoutKind kind = layoutKindOf(type);
            if (kind == LayoutKind::Struct && !type.isCompleted(ctx))
                return sema.waitCompleted(&type.payloadSymStruct(), node.srcViewRef(), node.tokRef());

            auto it = cache.entries.find(key);
            if (it == cache.entries.end())
            {
                // The first time we see this type in the cache: allocate and initialize its
                // runtime payload, then compute its dependency list.
                TypeGen::TypeGenCache::Entry entry;

                entry.rtTypeRef = rtTypeRefFor(tm, kind);

                // Make sure the runtime TypeInfo struct definition exists before we write
                // an instance of it into the 'DataSegment'.
                RESULT_VERIFY(ensureTypeInfoStructReady(sema, tm, entry.rtTypeRef, node));

                // Allocate the concrete runtime payload (TypeInfoStruct/TypeInfoPtr/...) in
                // the target storage and remember its offset.
                auto [offset, rtBase] = allocateTypeInfoPayload(storage, kind, type);
                entry.offset          = offset;

                TypeGen::TypeGenResult tmp;
                tmp.rtTypeRef = entry.rtTypeRef;
                tmp.offset    = entry.offset;

                // Fill the common fields that are independent of other type infos.
                initCommon(sema, storage, *rtBase, offset, type, tmp);

                // For structs, also emit the field list, but the per-field 'pointedType'
                // links will be fixed up later when dependencies are Done.
                if (kind == LayoutKind::Struct)
                    initStruct(sema, storage, *reinterpret_cast<Runtime::TypeInfoStruct*>(rtBase), offset, type, entry);

                // Compute direct dependencies required to wire this payload.
                entry.deps = computeDeps(tm, ctx, type, kind);
                it         = cache.entries.emplace(key, std::move(entry)).first;
            }

            auto& entry = it->second;
            if (entry.state == TypeGen::TypeGenCache::State::Done)
            {
                // Fully processed: pop and continue unwinding.
                stack.pop_back();
                inStack.erase(key);
                continue;
            }

            // Push the first unmet dependency.
            bool pushedDep = false;
            for (const TypeRef depKey : entry.deps)
            {
                if (depKey == key)
                    continue;

                const auto depIt = cache.entries.find(depKey);
                if (depIt != cache.entries.end() && depIt->second.state == TypeGen::TypeGenCache::State::Done)
                    continue;

                if (!inStack.contains(depKey))
                {
                    // Depth-first: process this dependency before completing 'key'.
                    stack.push_back(depKey);
                    inStack.insert(depKey);
                }

                pushedDep = true;
                break;
            }

            if (pushedDep)
                continue;

            // All deps are Done => wire relocations, then mark Done.
            wireRelocations(sema, cache, storage, key, entry, kind);
            entry.state = TypeGen::TypeGenCache::State::Done;
        }

        const auto it = cache.entries.find(typeRef);
        if (it == cache.entries.end() || it->second.state != TypeGen::TypeGenCache::State::Done)
            return Result::Pause;

        const auto& entry = it->second;
        result.offset     = entry.offset;
        result.rtTypeRef  = entry.rtTypeRef;

        const TypeInfo& structType = tm.get(result.rtTypeRef);
        result.span                = ByteSpan{storage.ptr<std::byte>(result.offset), structType.sizeOf(ctx)};

        sema.compiler().notifyAlive();
        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
