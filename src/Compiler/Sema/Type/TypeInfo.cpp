#include "pch.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Core/Utf8Helper.h"
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

    template<class T, std::size_t InlineCapacity>
    class RuntimeHashStackScope
    {
    public:
        RuntimeHashStackScope(SmallVector<T, InlineCapacity>& stack, const T& value) :
            stack_(&stack)
        {
            stack.push_back(value);
        }

        ~RuntimeHashStackScope()
        {
            stack_->pop_back();
        }

    private:
        SmallVector<T, InlineCapacity>* stack_ = nullptr;
    };

    RuntimeHashState& runtimeHashState()
    {
        SWC_ASSERT(g_RuntimeHashDepth != 0);
        return g_RuntimeHashState;
    }

    template<class T, std::size_t InlineCapacity>
    bool findStackDistance(uint32_t& outDistance, const SmallVector<T, InlineCapacity>& stack, const T& value) noexcept
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
        h                       = Math::hashCombine(h, static_cast<uint32_t>(typeInfo.kind()));
        h                       = Math::hashCombine(h, static_cast<uint32_t>(typeInfo.flags().get()));
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

    Symbol* typeBlockingSymbol(TaskContext& ctx, TypeRef tr)
    {
        if (!tr.isValid())
            return nullptr;
        return ctx.typeMgr().get(tr).getNotCompletedSymbol(ctx);
    }

    Symbol* directBlockingSymbol(Symbol* sym)
    {
        if (!sym || sym->isSemaCompleted())
            return nullptr;
        return sym;
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

        RuntimeHashStackScope<const SymbolFunction*, 32> functionScope(state.functions, &function);
        uint32_t h = Math::hash(static_cast<uint32_t>(function.callConvKind()));
        h          = Math::hashCombine(h, function.isClosure());
        h          = Math::hashCombine(h, function.isMethod());
        h          = Math::hashCombine(h, function.isThrowable());
        h          = Math::hashCombine(h, function.isConst());
        h          = Math::hashCombine(h, function.hasVariadicParam());
        h          = Math::hashCombine(h, stableTypeHash(ctx, function.returnTypeRef()));
        h          = Math::hashCombine(h, static_cast<uint32_t>(function.parameters().size()));
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

        RuntimeHashStackScope<ConstantRef, 32> constantScope(state.constants, cstRef);
        const ConstantValue& value = ctx.cstMgr().get(cstRef);
        uint32_t             h     = Math::hash(static_cast<uint32_t>(value.kind()));
        h                          = Math::hashCombine(h, stableTypeHash(ctx, value.typeRef()));

        switch (value.kind())
        {
            case ConstantKind::Bool:
                h = Math::hashCombine(h, value.getBool());
                break;
            case ConstantKind::Char:
                h = Math::hashCombine(h, static_cast<uint32_t>(value.getChar()));
                break;
            case ConstantKind::Rune:
                h = Math::hashCombine(h, static_cast<uint32_t>(value.getRune()));
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

TypeInfo::~TypeInfo()
{
    switch (kind_)
    {
        case TypeInfoKind::Array:
            std::destroy_at(&payloadArray_.dims);
            break;
        case TypeInfoKind::AggregateStruct:
        case TypeInfoKind::AggregateArray:
            std::destroy_at(&payloadAggregate_.types);
            std::destroy_at(&payloadAggregate_.names);
            std::destroy_at(&payloadAggregate_.fieldRefs);
            break;
        default:
            break;
    }
}

TypeRef TypeInfo::payloadTypeRef() const noexcept
{
    SWC_ASSERT(isTypeValue() || isAnyPointer() || isReference() || isSlice() || isAlias() || isTypedVariadic() || isCodeBlock());
    if (isAlias())
        return payloadAlias_.sym->underlyingTypeRef();
    return payloadTypeRef_.typeRef;
}

TypeInfo::TypeInfo(const TypeInfo& other) :
    kind_(other.kind_),
    flags_(other.flags_)
{
    switch (kind_)
    {
        case TypeInfoKind::Bool:
        case TypeInfoKind::Char:
        case TypeInfoKind::String:
        case TypeInfoKind::Void:
        case TypeInfoKind::Null:
        case TypeInfoKind::Any:
        case TypeInfoKind::Rune:
        case TypeInfoKind::CString:
        case TypeInfoKind::Variadic:
        case TypeInfoKind::TypeInfo:
        case TypeInfoKind::Undefined:
            break;

        case TypeInfoKind::Int:
            payloadInt_ = other.payloadInt_;
            break;

        case TypeInfoKind::Float:
            payloadFloat_ = other.payloadFloat_;
            break;

        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Reference:
        case TypeInfoKind::MoveReference:
        case TypeInfoKind::Slice:
        case TypeInfoKind::TypeValue:
        case TypeInfoKind::TypedVariadic:
        case TypeInfoKind::CodeBlock:
            payloadTypeRef_ = other.payloadTypeRef_;
            break;

        case TypeInfoKind::AggregateStruct:
        case TypeInfoKind::AggregateArray:
            std::construct_at(&payloadAggregate_.types, other.payloadAggregate_.types);
            std::construct_at(&payloadAggregate_.names, other.payloadAggregate_.names);
            std::construct_at(&payloadAggregate_.fieldRefs, other.payloadAggregate_.fieldRefs);
            break;

        case TypeInfoKind::Enum:
            payloadEnum_ = other.payloadEnum_;
            break;
        case TypeInfoKind::Struct:
            payloadStruct_ = other.payloadStruct_;
            break;
        case TypeInfoKind::Interface:
            payloadInterface_ = other.payloadInterface_;
            break;
        case TypeInfoKind::Alias:
            payloadAlias_ = other.payloadAlias_;
            break;

        case TypeInfoKind::Array:
            std::construct_at(&payloadArray_.dims, other.payloadArray_.dims);
            payloadArray_.typeRef = other.payloadArray_.typeRef;
            break;
        case TypeInfoKind::Function:
            payloadFunction_ = other.payloadFunction_;
            break;

        default:
            SWC_UNREACHABLE();
    }
}

TypeInfo::TypeInfo(TypeInfo&& other) noexcept :
    kind_(other.kind_),
    flags_(other.flags_)
{
    switch (kind_)
    {
        case TypeInfoKind::Bool:
        case TypeInfoKind::Char:
        case TypeInfoKind::String:
        case TypeInfoKind::Void:
        case TypeInfoKind::Null:
        case TypeInfoKind::Any:
        case TypeInfoKind::Rune:
        case TypeInfoKind::CString:
        case TypeInfoKind::Variadic:
        case TypeInfoKind::TypeInfo:
        case TypeInfoKind::Undefined:
            break;

        case TypeInfoKind::Int:
            payloadInt_ = other.payloadInt_;
            break;

        case TypeInfoKind::Float:
            payloadFloat_ = other.payloadFloat_;
            break;

        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Reference:
        case TypeInfoKind::MoveReference:
        case TypeInfoKind::Slice:
        case TypeInfoKind::TypeValue:
        case TypeInfoKind::TypedVariadic:
        case TypeInfoKind::CodeBlock:
            payloadTypeRef_ = other.payloadTypeRef_;
            break;

        case TypeInfoKind::AggregateStruct:
        case TypeInfoKind::AggregateArray:
            std::construct_at(&payloadAggregate_.types, std::move(other.payloadAggregate_.types));
            std::construct_at(&payloadAggregate_.names, std::move(other.payloadAggregate_.names));
            std::construct_at(&payloadAggregate_.fieldRefs, std::move(other.payloadAggregate_.fieldRefs));
            break;

        case TypeInfoKind::Enum:
            payloadEnum_ = other.payloadEnum_;
            break;
        case TypeInfoKind::Struct:
            payloadStruct_ = other.payloadStruct_;
            break;
        case TypeInfoKind::Interface:
            payloadInterface_ = other.payloadInterface_;
            break;
        case TypeInfoKind::Alias:
            payloadAlias_ = other.payloadAlias_;
            break;

        case TypeInfoKind::Array:
            std::construct_at(&payloadArray_.dims, std::move(other.payloadArray_.dims));
            payloadArray_.typeRef = other.payloadArray_.typeRef;
            break;
        case TypeInfoKind::Function:
            payloadFunction_ = other.payloadFunction_;
            break;

        default:
            SWC_UNREACHABLE();
    }
}

TypeInfo& TypeInfo::operator=(const TypeInfo& other)
{
    if (this == &other)
        return *this;
    this->~TypeInfo();
    new (this) TypeInfo(other);
    return *this;
}

TypeInfo& TypeInfo::operator=(TypeInfo&& other) noexcept
{
    if (this == &other)
        return *this;
    this->~TypeInfo();
    new (this) TypeInfo(std::move(other));
    return *this;
}

uint32_t TypeInfo::hash() const
{
    uint32_t h = Math::hash(static_cast<uint32_t>(kind_));
    h          = Math::hashCombine(h, static_cast<uint32_t>(flags_.get()));

    switch (kind_)
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
            h = Math::hashCombine(h, payloadInt_.bits);
            h = Math::hashCombine(h, static_cast<uint32_t>(payloadInt_.sign));
            return h;
        case TypeInfoKind::Float:
            h = Math::hashCombine(h, payloadFloat_.bits);
            return h;
        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Reference:
        case TypeInfoKind::MoveReference:
        case TypeInfoKind::Slice:
        case TypeInfoKind::TypeValue:
        case TypeInfoKind::TypedVariadic:
        case TypeInfoKind::CodeBlock:
            h = Math::hashCombine(h, payloadTypeRef_.typeRef.get());
            return h;

        case TypeInfoKind::AggregateStruct:
            h = Math::hashCombine(h, static_cast<uint32_t>(payloadAggregate_.types.size()));
            h = Math::hashCombine(h, static_cast<uint32_t>(payloadAggregate_.names.size()));
            return h;
        case TypeInfoKind::AggregateArray:
            h = Math::hashCombine(h, static_cast<uint32_t>(payloadAggregate_.types.size()));
            return h;
        case TypeInfoKind::Enum:
            h = Math::hashCombine(h, reinterpret_cast<uintptr_t>(payloadEnum_.sym));
            return h;
        case TypeInfoKind::Struct:
            h = Math::hashCombine(h, reinterpret_cast<uintptr_t>(payloadStruct_.sym));
            return h;
        case TypeInfoKind::Interface:
            h = Math::hashCombine(h, reinterpret_cast<uintptr_t>(payloadInterface_.sym));
            return h;
        case TypeInfoKind::Alias:
            h = Math::hashCombine(h, reinterpret_cast<uintptr_t>(payloadAlias_.sym));
            return h;
        case TypeInfoKind::Function:
            h = Math::hashCombine(h, payloadFunction_.sym->typeSignatureHash());
            return h;
        case TypeInfoKind::Array:
            h = Math::hashCombine(h, payloadArray_.typeRef.get());
            for (const auto dim : payloadArray_.dims)
                h = Math::hashCombine(h, static_cast<uint32_t>(dim));
            return h;

        default:
            SWC_UNREACHABLE();
    }
}

uint32_t TypeInfo::runtimeHash(const TaskContext& ctx) const
{
    RuntimeHashRootScope runtimeHashScope;
    uint32_t h = Math::hash(static_cast<uint32_t>(kind_));
    h          = Math::hashCombine(h, static_cast<uint32_t>(flags_.get()));

    switch (kind_)
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
            h = Math::hashCombine(h, payloadInt_.bits);
            h = Math::hashCombine(h, static_cast<uint32_t>(payloadInt_.sign));
            return h;
        case TypeInfoKind::Float:
            h = Math::hashCombine(h, payloadFloat_.bits);
            return h;
        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Reference:
        case TypeInfoKind::MoveReference:
        case TypeInfoKind::Slice:
        case TypeInfoKind::TypeValue:
        case TypeInfoKind::TypedVariadic:
        case TypeInfoKind::CodeBlock:
            h = Math::hashCombine(h, stableTypeHash(ctx, payloadTypeRef_.typeRef));
            return h;

        case TypeInfoKind::AggregateStruct:
            h = Math::hashCombine(h, static_cast<uint32_t>(payloadAggregate_.types.size()));
            h = Math::hashCombine(h, static_cast<uint32_t>(payloadAggregate_.names.size()));
            for (uint32_t i = 0; i < payloadAggregate_.types.size(); ++i)
            {
                h = Math::hashCombine(h, stableTypeHash(ctx, payloadAggregate_.types[i]));
                if (i < payloadAggregate_.names.size() && payloadAggregate_.names[i].isValid())
                {
                    const auto& id = ctx.idMgr().get(payloadAggregate_.names[i]);
                    h              = Math::hashCombine(h, Math::hash(id.name));
                }
                else
                    h = Math::hashCombine(h, 0u);
            }
            return h;
        case TypeInfoKind::AggregateArray:
            h = Math::hashCombine(h, static_cast<uint32_t>(payloadAggregate_.types.size()));
            for (const TypeRef elemTypeRef : payloadAggregate_.types)
                h = Math::hashCombine(h, stableTypeHash(ctx, elemTypeRef));
            return h;
        case TypeInfoKind::Enum:
            h = Math::hashCombine(h, stableSymbolHash(ctx, payloadSymEnum()));
            return h;
        case TypeInfoKind::Struct:
            h = Math::hashCombine(h, stableSymbolHash(ctx, payloadSymStruct()));
            return h;
        case TypeInfoKind::Interface:
            h = Math::hashCombine(h, stableSymbolHash(ctx, payloadSymInterface()));
            return h;
        case TypeInfoKind::Alias:
            h = Math::hashCombine(h, stableSymbolHash(ctx, payloadSymAlias()));
            return h;
        case TypeInfoKind::Function:
            h = Math::hashCombine(h, stableFunctionTypeHash(ctx, payloadSymFunction()));
            return h;
        case TypeInfoKind::Array:
            h = Math::hashCombine(h, stableTypeHash(ctx, payloadArray_.typeRef));
            for (const uint64_t dim : payloadArray_.dims)
                h = Math::hashCombine(h, dim);
            return h;

        default:
            SWC_UNREACHABLE();
    }
}

bool TypeInfo::operator==(const TypeInfo& other) const noexcept
{
    if (kind_ != other.kind_)
        return false;
    if (flags_ != other.flags_)
        return false;
    switch (kind_)
    {
        case TypeInfoKind::Bool:
        case TypeInfoKind::Char:
        case TypeInfoKind::String:
        case TypeInfoKind::Void:
        case TypeInfoKind::Null:
        case TypeInfoKind::Any:
        case TypeInfoKind::Rune:
        case TypeInfoKind::CString:
        case TypeInfoKind::Variadic:
        case TypeInfoKind::TypeInfo:
            return true;

        case TypeInfoKind::Int:
            return payloadInt_.bits == other.payloadInt_.bits && payloadInt_.sign == other.payloadInt_.sign;
        case TypeInfoKind::Float:
            return payloadFloat_.bits == other.payloadFloat_.bits;

        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Reference:
        case TypeInfoKind::MoveReference:
        case TypeInfoKind::Slice:
        case TypeInfoKind::TypeValue:
        case TypeInfoKind::TypedVariadic:
        case TypeInfoKind::CodeBlock:
            return payloadTypeRef_.typeRef == other.payloadTypeRef_.typeRef;

        case TypeInfoKind::AggregateStruct:
            if (payloadAggregate_.types.size() != other.payloadAggregate_.types.size())
                return false;
            if (payloadAggregate_.names.size() != other.payloadAggregate_.names.size())
                return false;
            for (uint32_t i = 0; i < payloadAggregate_.types.size(); ++i)
                if (payloadAggregate_.types[i] != other.payloadAggregate_.types[i] ||
                    payloadAggregate_.names[i] != other.payloadAggregate_.names[i])
                    return false;
            return true;
        case TypeInfoKind::AggregateArray:
            if (payloadAggregate_.types.size() != other.payloadAggregate_.types.size())
                return false;
            for (uint32_t i = 0; i < payloadAggregate_.types.size(); ++i)
                if (payloadAggregate_.types[i] != other.payloadAggregate_.types[i])
                    return false;
            return true;

        case TypeInfoKind::Enum:
            return payloadEnum_.sym == other.payloadEnum_.sym;
        case TypeInfoKind::Struct:
            return payloadStruct_.sym == other.payloadStruct_.sym;
        case TypeInfoKind::Interface:
            return payloadInterface_.sym == other.payloadInterface_.sym;
        case TypeInfoKind::Alias:
            return payloadAlias_.sym == other.payloadAlias_.sym;
        case TypeInfoKind::Function:
            return payloadFunction_.sym == other.payloadFunction_.sym;

        case TypeInfoKind::Array:
            if (payloadArray_.dims.size() != other.payloadArray_.dims.size())
                return false;
            if (payloadArray_.typeRef != other.payloadArray_.typeRef)
                return false;
            for (uint32_t i = 0; i < payloadArray_.dims.size(); ++i)
                if (payloadArray_.dims[i] != other.payloadArray_.dims[i])
                    return false;
            return true;

        default:
            SWC_UNREACHABLE();
    }
}

Utf8 TypeInfo::toName(const TaskContext& ctx) const
{
    Utf8 out;

    if (isNullable())
        out += "#null ";
    if (isConst())
        out += "const ";

    switch (kind_)
    {
        case TypeInfoKind::Bool:
            out += "bool";
            break;
        case TypeInfoKind::Char:
            out += "character";
            break;
        case TypeInfoKind::String:
            out += "string";
            break;
        case TypeInfoKind::Void:
            out += "void";
            break;
        case TypeInfoKind::Null:
            out += "null";
            break;
        case TypeInfoKind::Undefined:
            out += "undefined";
            break;
        case TypeInfoKind::Any:
            out += "any";
            break;
        case TypeInfoKind::Rune:
            out += "rune";
            break;
        case TypeInfoKind::CString:
            out += "cstring";
            break;
        case TypeInfoKind::CodeBlock:
        {
            const TypeInfo& type = ctx.typeMgr().get(payloadTypeRef_.typeRef);
            out += std::format("#code {}", type.toName(ctx));
            break;
        }
        case TypeInfoKind::TypeInfo:
            out += "typeinfo";
            break;
        case TypeInfoKind::AggregateStruct:
            out = "struct literal";
            break;
        case TypeInfoKind::AggregateArray:
            out = "array literal";
            break;

        case TypeInfoKind::Enum:
            out += payloadEnum_.sym->name(ctx);
            break;
        case TypeInfoKind::Struct:
            out += payloadStruct_.sym->name(ctx);
            break;
        case TypeInfoKind::Interface:
            out += payloadInterface_.sym->name(ctx);
            break;
        case TypeInfoKind::Alias:
            out += payloadAlias_.sym->name(ctx);
            break;
        case TypeInfoKind::Function:
            out += payloadFunction_.sym->computeName(ctx);
            break;

        case TypeInfoKind::TypeValue:
        {
            const TypeInfo& type = ctx.typeMgr().get(payloadTypeRef_.typeRef);
            out += std::format("typeinfo({})", type.toName(ctx));
            break;
        }

        case TypeInfoKind::ValuePointer:
        {
            const TypeInfo& type = ctx.typeMgr().get(payloadTypeRef_.typeRef);
            out += std::format("*{}", type.toName(ctx));
            break;
        }

        case TypeInfoKind::BlockPointer:
        {
            const TypeInfo& type = ctx.typeMgr().get(payloadTypeRef_.typeRef);
            out += std::format("[*] {}", type.toName(ctx));
            break;
        }

        case TypeInfoKind::Reference:
        {
            const TypeInfo& type = ctx.typeMgr().get(payloadTypeRef_.typeRef);
            out += std::format("&{}", type.toName(ctx));
            break;
        }
        case TypeInfoKind::MoveReference:
        {
            const TypeInfo& type = ctx.typeMgr().get(payloadTypeRef_.typeRef);
            out += std::format("&&{}", type.toName(ctx));
            break;
        }

        case TypeInfoKind::Int:
            if (payloadInt_.bits == 0)
            {
                if (payloadInt_.sign == Sign::Unsigned)
                    out += "unsigned integer"; // keep qualifiers
                else if (payloadInt_.sign == Sign::Signed)
                    out += "signed integer";
                else
                    out += "integer";
            }
            else
            {
                SWC_ASSERT(payloadInt_.sign != Sign::Unknown);
                out += payloadInt_.sign == Sign::Unsigned ? "u" : "s";
                out += std::to_string(payloadInt_.bits);
            }
            break;

        case TypeInfoKind::Float:
            if (payloadFloat_.bits == 0)
                out += "float"; // keep qualifiers
            else
            {
                out += "f";
                out += std::to_string(payloadFloat_.bits);
            }
            break;

        case TypeInfoKind::Slice:
        {
            const TypeInfo& type = ctx.typeMgr().get(payloadTypeRef_.typeRef);
            out += std::format("[..] {}", type.toName(ctx));
            break;
        }

        case TypeInfoKind::Array:
        {
            if (payloadArray_.dims.empty())
                out += "[?]";
            else
            {
                out += "[";
                for (size_t i = 0; i < payloadArray_.dims.size(); ++i)
                {
                    if (i != 0)
                        out += ", ";
                    out += std::to_string(payloadArray_.dims[i]);
                }
                out += "]";
            }
            const TypeInfo& elemType = ctx.typeMgr().get(payloadArray_.typeRef);
            if (!elemType.isArray())
                out += " ";
            out += elemType.toName(ctx);
            break;
        }

        case TypeInfoKind::Variadic:
            out += "...";
            break;
        case TypeInfoKind::TypedVariadic:
        {
            const TypeInfo& type = ctx.typeMgr().get(payloadTypeRef_.typeRef);
            out += std::format("{}...", type.toName(ctx));
            break;
        }

        default:
            SWC_UNREACHABLE();
    }

    return out;
}

Utf8 TypeInfo::toFamily(const TaskContext& ctx) const
{
    SWC_UNUSED(ctx);
    switch (kind_)
    {
        case TypeInfoKind::Bool:
            return "bool";
        case TypeInfoKind::Char:
            return "character";
        case TypeInfoKind::String:
            return "string";
        case TypeInfoKind::Void:
            return "void";
        case TypeInfoKind::Null:
            return "null";
        case TypeInfoKind::Undefined:
            return "undefined";
        case TypeInfoKind::Any:
            return "any";
        case TypeInfoKind::Rune:
            return "rune";
        case TypeInfoKind::CString:
            return "cstring";
        case TypeInfoKind::Enum:
            return "enum";
        case TypeInfoKind::Struct:
            return "struct";
        case TypeInfoKind::Interface:
            return "interface";
        case TypeInfoKind::Alias:
            return "alias";
        case TypeInfoKind::Function:
            return "function";
        case TypeInfoKind::CodeBlock:
            return "code";
        case TypeInfoKind::TypeInfo:
        case TypeInfoKind::TypeValue:
            return "typeinfo";
        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
            return "pointer";
        case TypeInfoKind::Reference:
            return "reference";
        case TypeInfoKind::MoveReference:
            return "move reference";
        case TypeInfoKind::Int:
            return "integer";
        case TypeInfoKind::Float:
            return "float";
        case TypeInfoKind::Slice:
            return "slice";
        case TypeInfoKind::Array:
            return "array";
        case TypeInfoKind::AggregateStruct:
        case TypeInfoKind::AggregateArray:
            return "aggregate";
        case TypeInfoKind::Variadic:
        case TypeInfoKind::TypedVariadic:
            return "variadic";
        default:
            SWC_UNREACHABLE();
    }
}

Utf8 TypeInfo::toArticleFamily(const TaskContext& ctx) const
{
    return Utf8Helper::addArticleAAn(toFamily(ctx));
}

TypeInfo TypeInfo::makeBool()
{
    return TypeInfo{TypeInfoKind::Bool};
}

TypeInfo TypeInfo::makeChar()
{
    return TypeInfo{TypeInfoKind::Char};
}

TypeInfo TypeInfo::makeString(TypeInfoFlags flags)
{
    return TypeInfo{TypeInfoKind::String, flags};
}

TypeInfo TypeInfo::makeInt(uint32_t bits, Sign sign)
{
    TypeInfo ti{TypeInfoKind::Int};
    ti.payloadInt_ = {.bits = bits, .sign = sign};
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeFloat(uint32_t bits)
{
    TypeInfo ti{TypeInfoKind::Float};
    ti.payloadFloat_ = {.bits = bits};
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeTypeValue(TypeRef typeRef)
{
    TypeInfo ti{TypeInfoKind::TypeValue};
    ti.payloadTypeRef_ = {.typeRef = typeRef};
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeRune()
{
    return TypeInfo{TypeInfoKind::Rune};
}

TypeInfo TypeInfo::makeAny(TypeInfoFlags flags)
{
    return TypeInfo{TypeInfoKind::Any, flags};
}

TypeInfo TypeInfo::makeVoid()
{
    return TypeInfo{TypeInfoKind::Void};
}

TypeInfo TypeInfo::makeNull()
{
    return TypeInfo{TypeInfoKind::Null};
}

TypeInfo TypeInfo::makeUndefined()
{
    return TypeInfo{TypeInfoKind::Undefined, TypeInfoFlagsE::Zero};
}

TypeInfo TypeInfo::makeCString(TypeInfoFlags flags)
{
    return TypeInfo{TypeInfoKind::CString, flags};
}

TypeInfo TypeInfo::makeTypeInfo(TypeInfoFlags flags)
{
    return TypeInfo{TypeInfoKind::TypeInfo, flags};
}

TypeInfo TypeInfo::makeEnum(SymbolEnum* sym)
{
    TypeInfo ti{TypeInfoKind::Enum};
    ti.payloadEnum_.sym = sym;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeStruct(SymbolStruct* sym)
{
    TypeInfo ti{TypeInfoKind::Struct};
    ti.payloadStruct_.sym = sym;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeInterface(SymbolInterface* sym)
{
    TypeInfo ti{TypeInfoKind::Interface};
    ti.payloadInterface_.sym = sym;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeAlias(SymbolAlias* sym)
{
    TypeInfo ti{TypeInfoKind::Alias};
    ti.payloadAlias_.sym = sym;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeValuePointer(TypeRef pointeeTypeRef, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::ValuePointer, flags};
    ti.payloadTypeRef_.typeRef = pointeeTypeRef;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeBlockPointer(TypeRef pointeeTypeRef, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::BlockPointer, flags};
    ti.payloadTypeRef_.typeRef = pointeeTypeRef;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeReference(TypeRef pointeeTypeRef, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::Reference, flags};
    ti.payloadTypeRef_.typeRef = pointeeTypeRef;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeMoveReference(TypeRef pointeeTypeRef, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::MoveReference, flags};
    ti.payloadTypeRef_.typeRef = pointeeTypeRef;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeSlice(TypeRef pointeeTypeRef, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::Slice, flags};
    ti.payloadTypeRef_.typeRef = pointeeTypeRef;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeArray(const std::span<uint64_t>& dims, TypeRef elementTypeRef, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::Array, flags};
    std::construct_at(&ti.payloadArray_.dims, dims.begin(), dims.end());
    ti.payloadArray_.typeRef = elementTypeRef;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeAggregateStruct(const std::span<IdentifierRef>& names, const std::span<TypeRef>& types)
{
    SWC_ASSERT(types.size() == names.size());
    TypeInfo ti{TypeInfoKind::AggregateStruct, TypeInfoFlagsE::Const};
    std::construct_at(&ti.payloadAggregate_.types, types.begin(), types.end());
    std::construct_at(&ti.payloadAggregate_.names, names.begin(), names.end());
    std::construct_at(&ti.payloadAggregate_.fieldRefs, types.size(), SourceCodeRef::invalid());
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeAggregateArray(const std::span<TypeRef>& types)
{
    TypeInfo ti{TypeInfoKind::AggregateArray, TypeInfoFlagsE::Const};
    std::construct_at(&ti.payloadAggregate_.types, types.begin(), types.end());
    std::construct_at(&ti.payloadAggregate_.names);
    std::construct_at(&ti.payloadAggregate_.fieldRefs, types.size(), SourceCodeRef::invalid());
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeFunction(SymbolFunction* sym, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::Function, flags};
    ti.payloadFunction_.sym = sym;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeVariadic()
{
    return TypeInfo{TypeInfoKind::Variadic};
}

TypeInfo TypeInfo::makeTypedVariadic(TypeRef typeRef)
{
    TypeInfo ti{TypeInfoKind::TypedVariadic};
    ti.payloadTypeRef_ = {.typeRef = typeRef};
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeCodeBlock(TypeRef typeRef)
{
    TypeInfo ti{TypeInfoKind::CodeBlock};
    ti.payloadTypeRef_ = {.typeRef = typeRef};
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

uint64_t TypeInfo::sizeOf(TaskContext& ctx) const
{
    switch (kind_)
    {
        case TypeInfoKind::Void:
        case TypeInfoKind::Undefined:
            return 0;

        case TypeInfoKind::Bool:
            return 1;

        case TypeInfoKind::Char:
        case TypeInfoKind::Rune:
            return 4;

        case TypeInfoKind::Int:
            return payloadInt_.bits / 8;
        case TypeInfoKind::Float:
            return payloadFloat_.bits / 8;

        case TypeInfoKind::CString:
        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Reference:
        case TypeInfoKind::MoveReference:
        case TypeInfoKind::Null:
        case TypeInfoKind::TypeInfo:
        case TypeInfoKind::CodeBlock:
            return 8;

        case TypeInfoKind::Function:
            return isLambdaClosure() ? sizeof(Runtime::ClosureValue) : 8;

        case TypeInfoKind::Slice:
        case TypeInfoKind::String:
        case TypeInfoKind::Interface:
        case TypeInfoKind::Any:
            return 16;

        case TypeInfoKind::Array:
        {
            uint64_t count = ctx.typeMgr().get(payloadArray_.typeRef).sizeOf(ctx);
            for (const uint64_t d : payloadArray_.dims)
                count *= d;
            return count;
        }

        case TypeInfoKind::Struct:
            return payloadSymStruct().sizeOf();
        case TypeInfoKind::Enum:
            return payloadSymEnum().sizeOf(ctx);
        case TypeInfoKind::Alias:
            return payloadSymAlias().sizeOf(ctx);

        case TypeInfoKind::Variadic:
        case TypeInfoKind::TypedVariadic:
            return 0;

        case TypeInfoKind::TypeValue:
            return ctx.typeMgr().get(payloadTypeRef_.typeRef).sizeOf(ctx);

        case TypeInfoKind::AggregateStruct:
        case TypeInfoKind::AggregateArray:
        {
            uint64_t size  = 0;
            uint32_t align = 1;
            for (const TypeRef tr : payloadAggregate_.types)
            {
                const TypeInfo& ty = ctx.typeMgr().get(tr);
                const uint32_t  a  = std::max<uint32_t>(ty.alignOf(ctx), 1);
                const uint64_t  s  = ty.sizeOf(ctx);
                if (!s)
                    continue;
                align = std::max(align, a);
                size  = ((size + static_cast<uint64_t>(a) - 1) / static_cast<uint64_t>(a)) * static_cast<uint64_t>(a);
                size += s;
            }
            size = ((size + static_cast<uint64_t>(align) - 1) / static_cast<uint64_t>(align)) * static_cast<uint64_t>(align);
            return size;
        }

        default:
            SWC_UNREACHABLE();
    }
}

uint32_t TypeInfo::alignOf(TaskContext& ctx) const
{
    switch (kind_)
    {
        case TypeInfoKind::Void:
            return 0;
        case TypeInfoKind::Bool:
            return 1;
        case TypeInfoKind::Char:
        case TypeInfoKind::Rune:
            return 4;
        case TypeInfoKind::Int:
        case TypeInfoKind::Float:
            return static_cast<uint32_t>(sizeOf(ctx));
        case TypeInfoKind::CString:
        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Reference:
        case TypeInfoKind::MoveReference:
        case TypeInfoKind::Slice:
        case TypeInfoKind::String:
        case TypeInfoKind::Interface:
        case TypeInfoKind::Any:
        case TypeInfoKind::Null:
        case TypeInfoKind::Undefined:
        case TypeInfoKind::Variadic:
        case TypeInfoKind::TypedVariadic:
        case TypeInfoKind::TypeInfo:
        case TypeInfoKind::CodeBlock:
            return 8;

        case TypeInfoKind::Function:
            return isLambdaClosure() ? alignof(Runtime::ClosureValue) : 8;

        case TypeInfoKind::AggregateStruct:
        case TypeInfoKind::AggregateArray:
        {
            uint32_t align = 1;
            for (const TypeRef tr : payloadAggregate_.types)
                align = std::max(align, ctx.typeMgr().get(tr).alignOf(ctx));
            return align;
        }

        case TypeInfoKind::Array:
            return ctx.typeMgr().get(payloadArray_.typeRef).alignOf(ctx);

        case TypeInfoKind::Struct:
            return payloadSymStruct().alignment();
        case TypeInfoKind::Enum:
            return payloadSymEnum().underlyingType(ctx).alignOf(ctx);
        case TypeInfoKind::Alias:
            return payloadSymAlias().alignOf(ctx);

        case TypeInfoKind::TypeValue:
            return ctx.typeMgr().get(payloadTypeRef_.typeRef).alignOf(ctx);

        default:
            SWC_UNREACHABLE();
    }
}

bool TypeInfo::isCompleted(TaskContext& ctx) const
{
    switch (kind_)
    {
        case TypeInfoKind::Struct:
            return payloadSymStruct().isSemaCompleted();
        case TypeInfoKind::Enum:
            return payloadSymEnum().isSemaCompleted();
        case TypeInfoKind::Interface:
            return payloadSymInterface().isSemaCompleted();
        case TypeInfoKind::Alias:
            return payloadSymAlias().isSemaCompleted();

        case TypeInfoKind::Array:
            return ctx.typeMgr().get(payloadArray_.typeRef).isCompleted(ctx);
        case TypeInfoKind::Function:
        {
            if (payloadFunction_.sym->returnTypeRef().isValid() && !ctx.typeMgr().get(payloadFunction_.sym->returnTypeRef()).isCompleted(ctx))
                return false;
            for (const auto& param : payloadFunction_.sym->parameters())
                if (!ctx.typeMgr().get(param->typeRef()).isCompleted(ctx))
                    return false;
            return true;
        }
        case TypeInfoKind::TypeValue:
            return ctx.typeMgr().get(payloadTypeRef_.typeRef).isCompleted(ctx);
        case TypeInfoKind::TypedVariadic:
            return ctx.typeMgr().get(payloadTypeRef_.typeRef).isCompleted(ctx);
        case TypeInfoKind::CodeBlock:
            return ctx.typeMgr().get(payloadTypeRef_.typeRef).isCompleted(ctx);
        case TypeInfoKind::AggregateStruct:
        case TypeInfoKind::AggregateArray:
            for (const TypeRef tr : payloadAggregate_.types)
                if (!ctx.typeMgr().get(tr).isCompleted(ctx))
                    return false;
            return true;
        default:
            break;
    }

    return true;
}

Symbol* TypeInfo::getSymbol() const
{
    switch (kind_)
    {
        case TypeInfoKind::Struct:
            return &payloadSymStruct();
        case TypeInfoKind::Enum:
            return &payloadSymEnum();
        case TypeInfoKind::Interface:
            return &payloadSymInterface();
        case TypeInfoKind::Alias:
            return &payloadSymAlias();
        case TypeInfoKind::Function:
            return &payloadSymFunction();
        default:
            break;
    }

    return nullptr;
}

Symbol* TypeInfo::getNotCompletedSymbol(TaskContext& ctx) const
{
    switch (kind_)
    {
        case TypeInfoKind::Struct:
            return directBlockingSymbol(&payloadSymStruct());
        case TypeInfoKind::Enum:
            return directBlockingSymbol(&payloadSymEnum());
        case TypeInfoKind::Interface:
            return directBlockingSymbol(&payloadSymInterface());
        case TypeInfoKind::Alias:
            return directBlockingSymbol(&payloadSymAlias());

        case TypeInfoKind::Function:
        {
            if (Symbol* sym = typeBlockingSymbol(ctx, payloadFunction_.sym->returnTypeRef()))
                return sym;

            for (const auto& param : payloadFunction_.sym->parameters())
            {
                if (Symbol* sym = typeBlockingSymbol(ctx, param->typeRef()))
                    return sym;
            }

            return directBlockingSymbol(&payloadSymFunction());
        }

        case TypeInfoKind::Array:
            return typeBlockingSymbol(ctx, payloadArray_.typeRef);

        case TypeInfoKind::TypeValue:
        case TypeInfoKind::TypedVariadic:
        case TypeInfoKind::CodeBlock:
            return typeBlockingSymbol(ctx, payloadTypeRef_.typeRef);

        case TypeInfoKind::AggregateStruct:
        case TypeInfoKind::AggregateArray:
            for (const TypeRef tr : payloadAggregate_.types)
                if (Symbol* sym = typeBlockingSymbol(ctx, tr))
                    return sym;
            return nullptr;
        default:
            break;
    }

    return nullptr;
}

bool TypeInfo::supportsNullableQualifier() const noexcept
{
    switch (kind_)
    {
        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Slice:
        case TypeInfoKind::String:
        case TypeInfoKind::CString:
        case TypeInfoKind::Any:
        case TypeInfoKind::TypeInfo:
            return true;

        default:
            return false;
    }
}

bool TypeInfo::isEnumFlags() const noexcept
{
    return isEnum() && payloadEnum_.sym->isEnumFlags();
}

bool TypeInfo::isLambdaClosure() const noexcept
{
    return isFunction() && payloadFunction_.sym->hasExtraFlag(SymbolFunctionFlagsE::Closure);
}

bool TypeInfo::isLambdaMethod() const noexcept
{
    return isFunction() && payloadFunction_.sym->hasExtraFlag(SymbolFunctionFlagsE::Method);
}

bool TypeInfo::isAnyTypeInfo(const TaskContext& ctx) const noexcept
{
    if (isTypeInfo())
        return true;
    if (!isConst())
        return false;
    if (!isValuePointer())
        return false;
    const TypeInfo& type = ctx.typeMgr().get(payloadTypeRef_.typeRef);
    if (!type.isStruct())
        return false;
    return type.payloadSymStruct().hasExtraFlag(SymbolStructFlagsE::TypeInfo);
}

bool TypeInfo::isPointerLikeAliasAware(const TaskContext& ctx) const noexcept
{
    if (isPointerLike())
        return true;
    if (!isAlias())
        return false;
    return ctx.typeMgr().get(payloadSymAlias().underlyingTypeRef()).isPointerLikeAliasAware(ctx);
}

bool TypeInfo::isConvertibleToBoolAliasAware(const TaskContext& ctx) const noexcept
{
    if (isConvertibleToBool())
        return true;
    if (!isAlias())
        return false;
    return ctx.typeMgr().get(payloadSymAlias().underlyingTypeRef()).isConvertibleToBoolAliasAware(ctx);
}

TypeRef TypeInfo::unwrap(const TaskContext& ctx, TypeRef defaultTypeRef, TypeExpand expandFlags) const noexcept
{
    auto result = typeRef_;

    while (true)
    {
        const TypeInfo& ty  = ctx.typeMgr().get(result);
        TypeRef         sub = TypeRef::invalid();

        if (expandFlags.has(TypeExpandE::Alias) && ty.isAlias())
            sub = ty.payloadAlias_.sym->underlyingTypeRef();
        else if (expandFlags.has(TypeExpandE::Enum) && ty.isEnum())
            sub = ty.payloadEnum_.sym->underlyingTypeRef();
        else if (expandFlags.has(TypeExpandE::Pointer) && ty.isAnyPointer())
            sub = ty.payloadTypeRef_.typeRef;
        else if (expandFlags.has(TypeExpandE::Array) && ty.isArray())
            sub = ty.payloadArray_.typeRef;
        else if (expandFlags.has(TypeExpandE::Slice) && ty.isSlice())
            sub = ty.payloadTypeRef_.typeRef;
        else if (expandFlags.has(TypeExpandE::Variadic) && ty.isTypedVariadic())
            sub = ty.payloadTypeRef_.typeRef;
        else if (expandFlags.has(TypeExpandE::Function) && ty.isFunction())
            sub = ty.payloadFunction_.sym->returnTypeRef();

        if (sub.isInvalid())
            break;
        result = sub;
    }

    if (result == typeRef_)
        return defaultTypeRef;
    return result;
}

TypeRef TypeInfo::dereferenceTypeRef(const TaskContext& ctx) const
{
    SWC_UNUSED(ctx);
    SWC_ASSERT(isPointerOrReference());
    return payloadTypeRef();
}

// ReSharper disable once CppPossiblyUninitializedMember
TypeInfo::TypeInfo(TypeInfoKind kind, TypeInfoFlags flags) :
    kind_(kind),
    flags_(flags)
{
}

SWC_END_NAMESPACE();
