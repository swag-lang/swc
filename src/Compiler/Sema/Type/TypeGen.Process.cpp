#include "pch.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Cast/CastFailure.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeGen.Internal.h"
#include "Compiler/Sema/Type/TypeGenGenericArg.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"
#include "Support/Core/DataSegment.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct TypeInfoWalk
    {
        TypeGen::TypeGenCache* cache = nullptr;
        SmallVector<TypeRef>   stack;

        ~TypeInfoWalk()
        {
            // A semantic pause abandons this walk before the cache ownership is released.
            // Its next owner must revisit every unfinished dependency from the start.
            for (const TypeRef typeRef : stack)
            {
                const auto found = cache->entries.find(typeRef);
                if (found != cache->entries.end())
                    found->second.onDfsStack = false;
            }
        }
    };

    bool shouldWaitReflectedMethodTyping(const SymbolFunction& symFunc)
    {
        // Reflection waits only for methods that can actually appear in runtime
        // metadata. Generic roots and compiler-only helpers do not need to hold up
        // TypeInfo generation because no concrete method entry will be emitted.
        if (symFunc.isIgnored() || symFunc.isAttribute() || symFunc.isEmpty())
            return false;
        if (symFunc.attributes().hasRtFlag(RtAttributeFlagsE::Macro | RtAttributeFlagsE::Mixin | RtAttributeFlagsE::Compiler))
            return false;

        const SymbolStruct* ownerStruct = symFunc.ownerStruct();
        if (ownerStruct && ownerStruct->isGenericRoot() && !ownerStruct->isGenericInstance())
            return false;

        if (symFunc.isGenericRoot() && !symFunc.isGenericInstance())
            return false;

        return true;
    }

    bool shouldWaitReflectedLifecycleSema(const TaskContext& ctx, const SymbolFunction& symFunc)
    {
        return SemaSpecOp::isGeneratedLifecycleWrapperName(symFunc.name(ctx));
    }

    void appendAttributeParamValueDeps(SmallVector<TypeRef>& deps, Sema& sema, ConstantRef valueCstRef)
    {
        if (!valueCstRef.isValid())
            return;

        // Attribute values are materialized as Runtime::Any in the TypeInfo payload.
        // Record both the declared value type and the precise boxed type so the
        // eventual payload can point at already-emitted metadata.
        TaskContext&         ctx = sema.ctx();
        const ConstantValue& cst = ctx.cstMgr().get(valueCstRef);
        if (cst.isNull())
            return;

        const TypeRef valueTypeRef = cst.typeRef();
        if (!valueTypeRef.isValid())
            return;

        deps.push_back(valueTypeRef);

        const TypeRef boxedValueTypeRef = SemaHelpers::preciseAnyBoxedValueTypeRef(sema, valueTypeRef, valueCstRef, AstNodeRef::invalid());
        if (boxedValueTypeRef.isValid() && boxedValueTypeRef != valueTypeRef)
            deps.push_back(boxedValueTypeRef);

        const TypeRef   typeInfoValueTypeRef = boxedValueTypeRef.isValid() ? boxedValueTypeRef : valueTypeRef;
        const TypeInfo& valueType            = ctx.typeMgr().get(typeInfoValueTypeRef);
        if (!valueType.isAnyTypeInfo(ctx) || !cst.isValuePointer())
            return;

        const auto*   typePtr        = reinterpret_cast<const void*>(cst.getValuePointer());
        const TypeRef pointedTypeRef = ctx.typeGen().getBackTypeRef(typePtr);
        if (pointedTypeRef.isValid())
            deps.push_back(pointedTypeRef);
    }

    void appendAttributeDeps(SmallVector<TypeRef>& deps, Sema& sema, const AttributeList& attributes)
    {
        for (const AttributeInstance& attribute : attributes.attributes)
        {
            if (attribute.symbol)
            {
                const TypeRef attributeTypeRef = attribute.symbol->typeRef();
                if (attributeTypeRef.isValid())
                    deps.push_back(attributeTypeRef);
            }

            for (const AttributeParamInstance& param : attribute.params)
                appendAttributeParamValueDeps(deps, sema, param.valueCstRef);
        }
    }

    void appendGenericArgDeps(SmallVector<TypeRef>& deps, const TaskContext& ctx, std::span<const GenericInstanceKey> genericArgs)
    {
        for (const GenericInstanceKey& arg : genericArgs)
        {
            const TypeRef valueTypeRef = TypeGenGenericArg::genericArgValueTypeRef(ctx, arg);
            if (!valueTypeRef.isValid())
                continue;

            deps.push_back(valueTypeRef);

            if (!arg.cstRef.isValid())
                continue;

            const ConstantValue& cst       = ctx.cstMgr().get(arg.cstRef);
            const TypeInfo&      valueType = ctx.typeMgr().get(valueTypeRef);
            if (!valueType.isAnyTypeInfo(ctx) || !cst.isValuePointer())
                continue;

            const auto*   typePtr        = reinterpret_cast<const void*>(cst.getValuePointer());
            const TypeRef pointedTypeRef = ctx.typeGen().getBackTypeRef(typePtr);
            if (pointedTypeRef.isValid())
                deps.push_back(pointedTypeRef);
        }
    }
}

SmallVector<TypeRef> TypeGen::computeDeps(TypeManager& tm, Sema& sema, const TypeInfo& type, LayoutKind kind)
{
    SmallVector<TypeRef> deps;
    TaskContext&         ctx = sema.ctx();

    // TypeInfo emission is a relocation graph problem. Collect every type that may
    // be referenced by the payload before reserving/writing the current entry so
    // pointers can be patched deterministically afterward.
    switch (kind)
    {
        case LayoutKind::Enum:
        {
            const SymbolEnum& symEnum = type.payloadSymEnum();
            deps.push_back(symEnum.underlyingTypeRef());
            appendAttributeDeps(deps, sema, symEnum.attributes());

            std::vector<const Symbol*> symbols;
            symEnum.getAllSymbols(symbols);

            for (const Symbol* symbol : symbols)
            {
                const auto* enumValue = symbol ? symbol->safeCast<SymbolEnumValue>() : nullptr;
                if (enumValue)
                    appendAttributeDeps(deps, sema, enumValue->attributes());
            }

            break;
        }

        case LayoutKind::Pointer:
            deps.push_back(TypeGenInternal::pointerLayoutDepTypeRef(tm, type));
            break;

        case LayoutKind::Slice:
        case LayoutKind::Alias:
        case LayoutKind::TypedVariadic:
        case LayoutKind::CodeBlock:
            deps.push_back(type.payloadTypeRef());
            break;

        case LayoutKind::Array:
        {
            const TypeRef pointedTypeRef = tm.arrayElementTypeRef(type);
            deps.push_back(pointedTypeRef);

            const TypeRef finalTypeRef = resolveArrayFinalTypeRef(tm, ctx, type);
            if (finalTypeRef != pointedTypeRef)
                deps.push_back(finalTypeRef);

            break;
        }

        case LayoutKind::Simd:
            deps.push_back(type.payloadSimdLaneTypeRef());
            break;

        case LayoutKind::Struct:
        {
            if (type.isAggregateStruct())
            {
                const auto& fieldTypes = type.payloadAggregate().types;
                deps.append(fieldTypes.data(), fieldTypes.size());
                break;
            }

            const SymbolStruct& symStruct = type.payloadSymStruct();
            if (symStruct.isGenericInstance())
            {
                const SymbolStruct* genericRoot = symStruct.genericRootSym();
                if (genericRoot && genericRoot->typeRef().isValid())
                    deps.push_back(genericRoot->typeRef());

                SmallVector<GenericInstanceKey> genericArgs;
                if (symStruct.tryGetGenericInstanceArgs(genericArgs))
                    appendGenericArgDeps(deps, ctx, genericArgs.span());
            }

            appendAttributeDeps(deps, sema, symStruct.attributes());

            for (const SymbolVariable* field : symStruct.fields())
            {
                if (!field)
                    continue;

                deps.push_back(field->typeRef());
                appendAttributeDeps(deps, sema, field->attributes());
            }

            if (symStruct.exportsRuntimeMethods(ctx))
            {
                for (const SymbolFunction* method : symStruct.methods())
                {
                    if (!method)
                        continue;

                    const TypeRef methodTypeRef = reflectedMethodTypeRef(ctx, *method);
                    if (methodTypeRef.isValid())
                        deps.push_back(methodTypeRef);

                    appendAttributeDeps(deps, sema, method->attributes());
                }
            }

            for (const SymbolImpl* itfImpl : symStruct.interfaces())
            {
                const SymbolInterface* symInterface = itfImpl ? itfImpl->symInterface() : nullptr;
                if (symInterface && symInterface->typeRef().isValid())
                    deps.push_back(symInterface->typeRef());
            }

            break;
        }

        case LayoutKind::Func:
        {
            const SymbolFunction& symFunc = type.payloadSymFunction();
            if (!symFunc.isAttribute())
                appendAttributeDeps(deps, sema, symFunc.attributes());

            if (symFunc.isGenericInstance())
            {
                SmallVector<GenericInstanceKey> genericArgs;
                if (symFunc.tryGetGenericInstanceArgs(ctx, genericArgs))
                    appendGenericArgDeps(deps, ctx, genericArgs.span());
            }

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
                appendAttributeDeps(deps, sema, param->attributes());
            }

            break;
        }

        default:
            break;
    }

    return deps;
}

Result TypeGen::processTypeInfo(Sema& sema, TypeGenResult& result, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenCache& cache)
{
    TaskContext&   ctx  = sema.ctx();
    TypeManager&   tm   = ctx.typeMgr();
    const AstNode& node = sema.node(ownerNodeRef);

    // Allocate each payload before walking its dependencies, then wire relocations
    // when the walk returns to it. An explicit DFS stack avoids deep recursion
    // and lets semantic waits abandon the walk without discarding cached payloads.
    TypeInfoWalk walk{.cache = &cache};
    auto&        stack = walk.stack;
    stack.push_back(typeRef);

    while (!stack.empty())
    {
        const TypeRef   key  = stack.back();
        const TypeInfo& type = tm.get(key);

        const LayoutKind kind = layoutKindOf(type);
        if (type.isFunction())
        {
            // Attribute reflection only needs the typed function signature: waiting on
            // full sema here can deadlock while user attributes are themselves being
            // reflected during sema. Anonymous '#type func(...)' signatures use a
            // synthetic SymbolFunction that never goes through full declaration/body
            // sema, so runtime type info only depends on completed parameter and
            // return types -- which means we still need to wait for non-attributes.
            const Symbol* sym = type.getSymbol();
            if (!sym || !sym->isAttribute())
                SWC_RESULT(sema.waitSemaCompleted(&type, ownerNodeRef));
        }
        else if (const Symbol* sym = type.getSymbol())
        {
            SWC_RESULT(sema.waitSemaCompleted(sym, node.codeRef()));
        }

        if (kind == LayoutKind::Struct && type.isStruct() && !type.isAggregateStruct())
        {
            const SymbolStruct& symStruct = type.payloadSymStruct();
            for (const SymbolFunction* method : symStruct.declaredMethods())
            {
                if (!method || !shouldWaitReflectedMethodTyping(*method))
                    continue;

                SWC_RESULT(sema.waitTyped(method, node.codeRef()));

                // Lifecycle typeinfo must not cache a direct hook while its generated wrapper is
                // still in flight, otherwise reflection can freeze the wrong function pointer.
                if (shouldWaitReflectedLifecycleSema(sema.ctx(), *method))
                    SWC_RESULT(sema.waitSemaCompleted(method, node.codeRef()));
            }

            if (!symStruct.isGenericRoot() || symStruct.isGenericInstance())
            {
                for (const SymbolImpl* impl : symStruct.interfaces())
                {
                    CastFailure  failure;
                    const Result constraints = impl->validateInterfaceConstraints(sema, failure);
                    if (constraints == Result::Pause || (constraints == Result::Error && failure.diagId == DiagnosticId::None))
                        return constraints;
                }
            }
        }

        auto it = cache.entries.find(key);
        if (it == cache.entries.end())
        {
            TypeGenCache::Entry entry;

            // Runtime flags include whether the type has a complete implicit default.
            // Arrays and aliases do not necessarily have a root symbol to wait on above,
            // so make sure every value dependency is typed before freezing that flag.
            SWC_RESULT(SymbolStruct::waitTypeImplicitDefaultReady(sema, key, ownerNodeRef));

            // Make sure the runtime TypeInfo struct definition exists before we write
            // an instance of it into the 'DataSegment'.
            SWC_RESULT(rtTypeRefFor(sema, kind, entry.rtTypeRef, node.codeRef()));

            auto [offset, rtBase] = allocateTypeInfoPayload(storage, kind);

            entry.offset = offset;
            initTypeInfoPayload(sema, storage, *rtBase, offset, kind, key, type, entry);

            entry.deps = computeDeps(tm, sema, type, kind);

            // The payload is itself a DynCast instance of its concrete metadata struct.
            entry.deps.push_back(entry.rtTypeRef);

            // Unqualified types would only add a self-dependency, which the walk ignores.
            if (type.isConst() || type.isNullable())
            {
                TypeInfo unqualified = type;
                unqualified.removeFlag(TypeInfoFlagsE::Const);
                unqualified.removeFlag(TypeInfoFlagsE::Nullable);
                entry.deps.push_back(tm.addType(unqualified));
            }

            it = cache.entries.emplace(key, std::move(entry)).first;
        }

        auto& entry = it->second;
        if (entry.state == TypeGenCache::State::Done)
        {
            entry.onDfsStack = false;
            stack.pop_back();
            continue;
        }

        if (!entry.onDfsStack)
        {
            SWC_ASSERT(entry.deps.size() <= std::numeric_limits<uint32_t>::max());

            entry.onDfsStack     = true;
            entry.nextDependency = 0;
        }

        bool pushedDep = false;
        while (entry.nextDependency < entry.deps.size())
        {
            const TypeRef depKey = entry.deps[entry.nextDependency++];
            if (depKey == key)
                continue;

            const auto depIt = cache.entries.find(depKey);
            if (depIt != cache.entries.end())
            {
                if (depIt->second.state == TypeGenCache::State::Done)
                    continue;

                // Revisit unfinished entries left by an earlier semantic pause.
                // An entry on this walk's stack instead closes a cycle: its payload
                // already has a reserved offset, so relocation wiring can proceed.
                if (depIt->second.onDfsStack)
                    continue;
            }

            stack.push_back(depKey);
            pushedDep = true;
            break;
        }

        if (pushedDep)
            continue;

        // Cyclic dependencies already have payload offsets reserved for wiring.
        wireRelocations(sema, cache, storage, key, entry, kind);
        entry.state = TypeGenCache::State::Done;

        if (!entry.backRefPublished)
            cache.pendingBackRefs.push_back(key);
    }

    const auto it = cache.entries.find(typeRef);
    if (it == cache.entries.end() || it->second.state != TypeGenCache::State::Done)
        return Result::Pause;

    const auto& entry = it->second;

    result.offset    = entry.offset;
    result.rtTypeRef = entry.rtTypeRef;

    const TypeInfo& structType = tm.get(result.rtTypeRef);

    result.span = std::span{storage.ptr<std::byte>(result.offset), structType.sizeOf(ctx)};

    return Result::Continue;
}

SWC_END_NAMESPACE();
