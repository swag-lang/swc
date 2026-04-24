#include "pch.h"
#include "Compiler/Sema/Type/TypeRuntimeHash.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Math/Hash.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_TYPE_HASH_CYCLE     = 0xB71A5C1Eu;
    constexpr uint32_t K_CONSTANT_HASH_CYCLE = 0xC06A71CEu;
    constexpr uint32_t K_FUNCTION_HASH_CYCLE = 0xF0C7A11Du;

    struct RuntimeHashState
    {
        SmallVector<TypeRef, 64>               types;
        SmallVector<ConstantRef, 32>           constants;
        SmallVector<const SymbolFunction*, 32> functions;
    };

    thread_local RuntimeHashState g_RuntimeHashState;
    thread_local uint32_t         g_RuntimeHashDepth = 0;

    void clearRuntimeHashState()
    {
        g_RuntimeHashState.types.clear();
        g_RuntimeHashState.constants.clear();
        g_RuntimeHashState.functions.clear();
    }

    class RuntimeHashRootScope
    {
    public:
        RuntimeHashRootScope()
        {
            ownsState_ = g_RuntimeHashDepth == 0;
            if (ownsState_)
                clearRuntimeHashState();
            ++g_RuntimeHashDepth;
        }

        ~RuntimeHashRootScope()
        {
            SWC_ASSERT(g_RuntimeHashDepth != 0);
            --g_RuntimeHashDepth;
            if (ownsState_)
                clearRuntimeHashState();
        }

    private:
        bool ownsState_ = false;
    };

    template<class T, std::size_t N>
    class RuntimeHashStackScope
    {
    public:
        RuntimeHashStackScope(SmallVector<T, N>& stack, const T& value) :
            stack_(&stack)
        {
            stack.push_back(value);
        }

        ~RuntimeHashStackScope()
        {
            stack_->pop_back();
        }

    private:
        SmallVector<T, N>* stack_ = nullptr;
    };

    RuntimeHashState& runtimeHashState()
    {
        SWC_ASSERT(g_RuntimeHashDepth != 0);
        return g_RuntimeHashState;
    }

    template<class T, std::size_t N>
    bool findStackDistance(uint32_t& outDistance, const SmallVector<T, N>& stack, const T& value) noexcept
    {
        for (size_t i = stack.size(); i > 0; --i)
        {
            const size_t index = i - 1;
            if (stack[index] != value)
                continue;

            outDistance = static_cast<uint32_t>(stack.size() - index);
            return true;
        }

        return false;
    }

    uint32_t cycleHash(uint32_t tag, uint32_t distance)
    {
        uint32_t h = Math::hash(tag);
        h          = Math::hashCombine(h, distance);
        return h;
    }

    uint32_t typeCycleHash(const TaskContext& ctx, TypeRef typeRef, uint32_t distance)
    {
        const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
        uint32_t        h        = cycleHash(K_TYPE_HASH_CYCLE, distance);
        h                        = Math::hashCombine(h, static_cast<uint32_t>(typeInfo.kind()));
        h                        = Math::hashCombine(h, static_cast<uint32_t>(typeInfo.flags().get()));
        return h;
    }

    uint32_t constantCycleHash(const TaskContext& ctx, ConstantRef cstRef, uint32_t distance)
    {
        const ConstantValue& value = ctx.cstMgr().get(cstRef);
        uint32_t             h     = cycleHash(K_CONSTANT_HASH_CYCLE, distance);
        h                          = Math::hashCombine(h, static_cast<uint32_t>(value.kind()));
        return h;
    }

    uint32_t functionCycleHash(const SymbolFunction& function, uint32_t distance)
    {
        uint32_t h = cycleHash(K_FUNCTION_HASH_CYCLE, distance);
        h          = Math::hashCombine(h, static_cast<uint32_t>(function.callConvKind()));
        h          = Math::hashCombine(h, function.isClosure());
        h          = Math::hashCombine(h, function.isMethod());
        h          = Math::hashCombine(h, function.isThrowable());
        h          = Math::hashCombine(h, function.isConst());
        h          = Math::hashCombine(h, function.hasVariadicParam());
        h          = Math::hashCombine(h, static_cast<uint32_t>(function.parameters().size()));
        return h;
    }

    uint32_t stableTypeHash(const TaskContext& ctx, TypeRef typeRef);
    uint32_t stableConstantHash(const TaskContext& ctx, ConstantRef cstRef);

    void combineSymbolBaseHash(uint32_t& h, const TaskContext& ctx, const Symbol& symbol)
    {
        const Utf8 fullName = symbol.getFullScopedName(ctx);
        h                   = Math::hashCombine(h, Math::hash(fullName.view()));
        if (symbol.decl())
        {
            h = Math::hashCombine(h, symbol.srcViewRef().get());
            h = Math::hashCombine(h, symbol.tokRef().get());
        }
    }

    void combineGenericArgsHash(uint32_t& h, const TaskContext& ctx, std::span<const GenericInstanceKey> args)
    {
        h = Math::hashCombine(h, static_cast<uint32_t>(args.size()));
        for (const GenericInstanceKey& arg : args)
        {
            const bool hasTypeRef = arg.typeRef.isValid();
            const bool hasCstRef  = arg.cstRef.isValid();

            h = Math::hashCombine(h, hasTypeRef);
            if (hasTypeRef)
                h = Math::hashCombine(h, stableTypeHash(ctx, arg.typeRef));

            h = Math::hashCombine(h, hasCstRef);
            if (hasCstRef)
                h = Math::hashCombine(h, stableConstantHash(ctx, arg.cstRef));
        }
    }

    uint32_t stableSymbolHash(const TaskContext& ctx, const Symbol& symbol)
    {
        uint32_t h = Math::hash(static_cast<uint32_t>(symbol.kind()));

        if (const auto* symStruct = symbol.safeCast<SymbolStruct>())
        {
            const SymbolStruct* root = symStruct;
            if (symStruct->isGenericInstance())
            {
                root = symStruct->genericRootSym();
                SWC_ASSERT(root != nullptr);

                SmallVector<GenericInstanceKey> args;
                if (root && root->tryGetGenericInstanceArgs(*symStruct, args))
                {
                    combineSymbolBaseHash(h, ctx, *root);
                    combineGenericArgsHash(h, ctx, args.span());
                    return h;
                }
            }

            combineSymbolBaseHash(h, ctx, *root);
            return h;
        }

        if (const auto* symFunction = symbol.safeCast<SymbolFunction>())
        {
            const SymbolFunction* root = symFunction;
            if (symFunction->isGenericInstance())
            {
                root = symFunction->genericRootSym();
                SWC_ASSERT(root != nullptr);

                SmallVector<GenericInstanceKey> args;
                if (root && root->genericInstanceStorage(ctx).tryGetArgs(*symFunction, args))
                {
                    combineSymbolBaseHash(h, ctx, *root);
                    combineGenericArgsHash(h, ctx, args.span());
                    return h;
                }
            }

            combineSymbolBaseHash(h, ctx, *root);
            return h;
        }

        combineSymbolBaseHash(h, ctx, symbol);
        return h;
    }

    uint32_t stableFunctionTypeHash(const TaskContext& ctx, const SymbolFunction& function)
    {
        RuntimeHashState& state = runtimeHashState();
        uint32_t          cycleDistance;
        if (findStackDistance(cycleDistance, state.functions, &function))
            return functionCycleHash(function, cycleDistance);

        RuntimeHashStackScope functionScope(state.functions, &function);
        uint32_t              h = Math::hash(static_cast<uint32_t>(function.callConvKind()));
        h                       = Math::hashCombine(h, function.isClosure());
        h                       = Math::hashCombine(h, function.isMethod());
        h                       = Math::hashCombine(h, function.isThrowable());
        h                       = Math::hashCombine(h, function.isConst());
        h                       = Math::hashCombine(h, function.hasVariadicParam());
        h                       = Math::hashCombine(h, stableTypeHash(ctx, function.returnTypeRef()));
        h                       = Math::hashCombine(h, static_cast<uint32_t>(function.parameters().size()));
        for (const SymbolVariable* param : function.parameters())
        {
            SWC_ASSERT(param != nullptr);
            h = Math::hashCombine(h, stableTypeHash(ctx, param->typeRef()));
        }

        return h;
    }

    uint32_t stableConstantHash(const TaskContext& ctx, ConstantRef cstRef)
    {
        if (!cstRef.isValid())
            return 0;

        RuntimeHashState& state = runtimeHashState();
        uint32_t          cycleDistance;
        if (findStackDistance(cycleDistance, state.constants, cstRef))
            return constantCycleHash(ctx, cstRef, cycleDistance);

        RuntimeHashStackScope constantScope(state.constants, cstRef);
        const ConstantValue&  value = ctx.cstMgr().get(cstRef);
        uint32_t              h     = Math::hash(static_cast<uint32_t>(value.kind()));
        h                           = Math::hashCombine(h, stableTypeHash(ctx, value.typeRef()));

        switch (value.kind())
        {
            case ConstantKind::Bool:
                h = Math::hashCombine(h, value.getBool());
                break;
            case ConstantKind::Char:
                h = Math::hashCombine(h, value.getChar());
                break;
            case ConstantKind::Rune:
                h = Math::hashCombine(h, value.getRune());
                break;
            case ConstantKind::String:
                h = Math::hashCombine(h, Math::hash(value.getString()));
                break;
            case ConstantKind::Struct:
                h = Math::hashCombine(h, Math::hash(value.getStruct()));
                break;
            case ConstantKind::Array:
                h = Math::hashCombine(h, Math::hash(value.getArray()));
                break;
            case ConstantKind::AggregateStruct:
            case ConstantKind::AggregateArray:
                h = Math::hashCombine(h, static_cast<uint32_t>(value.getAggregate().size()));
                for (const ConstantRef nestedRef : value.getAggregate())
                    h = Math::hashCombine(h, stableConstantHash(ctx, nestedRef));
                break;
            case ConstantKind::Int:
                h = Math::hashCombine(h, value.getInt().hash());
                break;
            case ConstantKind::Float:
                h = Math::hashCombine(h, value.getFloat().hash());
                break;
            case ConstantKind::ValuePointer:
                h = Math::hashCombine(h, value.getValuePointer());
                break;
            case ConstantKind::BlockPointer:
                h = Math::hashCombine(h, value.getBlockPointer());
                break;
            case ConstantKind::Slice:
                h = Math::hashCombine(h, Math::hash(value.getSlice()));
                h = Math::hashCombine(h, value.getSliceCount());
                break;
            case ConstantKind::Null:
            case ConstantKind::Undefined:
                break;
            case ConstantKind::TypeValue:
                h = Math::hashCombine(h, stableTypeHash(ctx, value.getTypeValue()));
                break;
            case ConstantKind::EnumValue:
                h = Math::hashCombine(h, stableConstantHash(ctx, value.getEnumValue()));
                break;

            default:
                SWC_UNREACHABLE();
        }

        return h;
    }

    uint32_t stableTypeHash(const TaskContext& ctx, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return 0;

        RuntimeHashState& state = runtimeHashState();
        uint32_t          cycleDistance;
        if (findStackDistance(cycleDistance, state.types, typeRef))
            return typeCycleHash(ctx, typeRef, cycleDistance);

        RuntimeHashStackScope<TypeRef, 64> typeScope(state.types, typeRef);
        return ctx.typeMgr().get(typeRef).runtimeHash(ctx);
    }
}

uint32_t TypeRuntimeHash::compute(const TaskContext& ctx, const TypeInfo& typeInfo)
{
    RuntimeHashRootScope runtimeHashScope;
    uint32_t             h = Math::hash(static_cast<uint32_t>(typeInfo.kind_));
    h                      = Math::hashCombine(h, static_cast<uint32_t>(typeInfo.flags_.get()));

    switch (typeInfo.kind_)
    {
        case TypeInfoKind::Bool:
        case TypeInfoKind::Char:
        case TypeInfoKind::String:
        case TypeInfoKind::Void:
        case TypeInfoKind::Any:
        case TypeInfoKind::Rune:
        case TypeInfoKind::CString:
        case TypeInfoKind::Null:
        case TypeInfoKind::Undefined:
        case TypeInfoKind::Variadic:
        case TypeInfoKind::TypeInfo:
            return h;

        case TypeInfoKind::Int:
            h = Math::hashCombine(h, typeInfo.payloadInt_.bits);
            h = Math::hashCombine(h, static_cast<uint32_t>(typeInfo.payloadInt_.sign));
            return h;
        case TypeInfoKind::Float:
            h = Math::hashCombine(h, typeInfo.payloadFloat_.bits);
            return h;
        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Reference:
        case TypeInfoKind::MoveReference:
        case TypeInfoKind::Slice:
        case TypeInfoKind::TypeValue:
        case TypeInfoKind::TypedVariadic:
        case TypeInfoKind::CodeBlock:
            h = Math::hashCombine(h, stableTypeHash(ctx, typeInfo.payloadTypeRef_.typeRef));
            return h;

        case TypeInfoKind::AggregateStruct:
            h = Math::hashCombine(h, static_cast<uint32_t>(typeInfo.payloadAggregate_.types.size()));
            h = Math::hashCombine(h, static_cast<uint32_t>(typeInfo.payloadAggregate_.names.size()));
            for (uint32_t i = 0; i < typeInfo.payloadAggregate_.types.size(); ++i)
            {
                h = Math::hashCombine(h, stableTypeHash(ctx, typeInfo.payloadAggregate_.types[i]));
                if (i < typeInfo.payloadAggregate_.names.size() && typeInfo.payloadAggregate_.names[i].isValid())
                {
                    const auto& id = ctx.idMgr().get(typeInfo.payloadAggregate_.names[i]);
                    h              = Math::hashCombine(h, Math::hash(id.name));
                }
                else
                    h = Math::hashCombine(h, 0u);
            }
            return h;
        case TypeInfoKind::AggregateArray:
            h = Math::hashCombine(h, static_cast<uint32_t>(typeInfo.payloadAggregate_.types.size()));
            for (const TypeRef elemTypeRef : typeInfo.payloadAggregate_.types)
                h = Math::hashCombine(h, stableTypeHash(ctx, elemTypeRef));
            return h;
        case TypeInfoKind::Enum:
            h = Math::hashCombine(h, stableSymbolHash(ctx, typeInfo.payloadSymEnum()));
            return h;
        case TypeInfoKind::Struct:
            h = Math::hashCombine(h, stableSymbolHash(ctx, typeInfo.payloadSymStruct()));
            return h;
        case TypeInfoKind::Interface:
            h = Math::hashCombine(h, stableSymbolHash(ctx, typeInfo.payloadSymInterface()));
            return h;
        case TypeInfoKind::Alias:
            h = Math::hashCombine(h, stableSymbolHash(ctx, typeInfo.payloadSymAlias()));
            return h;
        case TypeInfoKind::Function:
            h = Math::hashCombine(h, stableFunctionTypeHash(ctx, typeInfo.payloadSymFunction()));
            return h;
        case TypeInfoKind::Array:
            h = Math::hashCombine(h, stableTypeHash(ctx, typeInfo.payloadArray_.typeRef));
            for (const uint64_t dim : typeInfo.payloadArray_.dims)
                h = Math::hashCombine(h, dim);
            return h;

        default:
            SWC_UNREACHABLE();
    }
}

uint32_t TypeInfo::runtimeHash(const TaskContext& ctx) const
{
    return TypeRuntimeHash::compute(ctx, *this);
}

SWC_END_NAMESPACE();
