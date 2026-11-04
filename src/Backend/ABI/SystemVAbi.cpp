#include "pch.h"
#include "Backend/ABI/SystemVAbi.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace SystemVAbi
{
    namespace
    {
        Class mergeClass(const Class first, const Class second)
        {
            if (first == second || second == Class::None)
                return first;
            if (first == Class::None)
                return second;
            if (first == Class::Memory || second == Class::Memory)
                return Class::Memory;
            if (first == Class::Integer || second == Class::Integer)
                return Class::Integer;
            return Class::Sse;
        }

        void markMemory(Classification& type)
        {
            type.classes = {Class::Memory, Class::None};
        }

        void mergeRange(Classification& into, const uint32_t offset, const uint32_t size, const Class kind)
        {
            if (!size)
                return;
            SWC_ASSERT(offset + size <= into.size && offset + size <= 16);
            for (uint32_t index = offset / 8; index <= (offset + size - 1) / 8; ++index)
                into.classes[index] = mergeClass(into.classes[index], kind);
        }

        bool classifyField(TaskContext& ctx, Classification& into, const TypeInfo& input, const uint32_t offset)
        {
            if (into.memory())
                return true;
            const TypeInfo& type = input.unwrapAliasEnumTypeOrSelf(ctx);
            const uint64_t size = type.sizeOf(ctx);
            if (!size)
                return true;
            const uint32_t alignment = std::max(type.alignOf(ctx), 1u);
            if (size > 16 || offset % alignment)
            {
                markMemory(into);
                return true;
            }
            SWC_ASSERT(offset + size <= into.size);
            if (type.isBool() || type.isCharRune() || type.isPointerOrReference() || type.isNull() || type.isAnyPointerOrCString() || type.isTypeInfo() || (type.isFunction() && !type.isLambdaClosure()))
            {
                mergeRange(into, offset, static_cast<uint32_t>(size), Class::Integer);
                return true;
            }
            if (type.isInt())
            {
                if (type.payloadIntBits() > 128 || type.payloadIntBits() % 8)
                    return false;
                mergeRange(into, offset, static_cast<uint32_t>(size), Class::Integer);
                return true;
            }
            if (type.isFloat() && (type.payloadFloatBits() == 32 || type.payloadFloatBits() == 64))
            {
                mergeRange(into, offset, static_cast<uint32_t>(size), Class::Sse);
                return true;
            }
            if (type.isSimd() || (type.isFloat() && type.payloadFloatBits() == 128))
            {
                mergeRange(into, offset, 8, Class::Sse);
                mergeRange(into, offset + 8, 8, Class::SseUp);
                return true;
            }
            if (type.isStringOrSlice() || type.isInterface() || type.isAny() || (type.isFunction() && type.isLambdaClosure()))
            {
                mergeRange(into, offset, static_cast<uint32_t>(size), Class::Integer);
                return true;
            }
            if (type.isStruct())
            {
                const SymbolStruct& record = type.payloadSymStruct();
                if (record.isTagged() && !classifyField(ctx, into, ctx.typeMgr().get(record.taggedTypeRef()), offset))
                    return false;
                for (const uint32_t slot : record.dynamicSlotOffsets())
                {
                    if (!classifyField(ctx, into, ctx.typeMgr().get(ctx.typeMgr().typeValuePtrVoid()), offset + slot))
                        return false;
                }
                for (const SymbolVariable* field : record.fields())
                {
                    if (!classifyField(ctx, into, ctx.typeMgr().get(field->typeRef()), offset + field->offset()))
                        return false;
                }
                return true;
            }
            if (type.isArray())
            {
                const TypeInfo& element = ctx.typeMgr().get(type.payloadArrayElemTypeRef());
                const uint64_t stride = element.sizeOf(ctx);
                if (!stride)
                    return true;
                for (uint32_t cursor = 0; cursor < size; cursor += static_cast<uint32_t>(stride))
                {
                    if (!classifyField(ctx, into, element, offset + cursor))
                        return false;
                }
                return true;
            }
            if (type.isAggregate())
            {
                uint32_t cursor = 0;
                for (const TypeRef fieldRef : type.payloadAggregate().types)
                {
                    const TypeInfo& field = ctx.typeMgr().get(fieldRef);
                    const uint64_t fieldSize = field.sizeOf(ctx);
                    if (!fieldSize)
                        continue;
                    const uint32_t align = std::max(field.alignOf(ctx), 1u);
                    cursor = (cursor + align - 1) / align * align;
                    if (!classifyField(ctx, into, field, offset + cursor))
                        return false;
                    cursor += static_cast<uint32_t>(fieldSize);
                }
                return true;
            }
            return false;
        }
    }

    uint32_t Classification::integerRegisters() const
    {
        return static_cast<uint32_t>(std::ranges::count(classes, Class::Integer));
    }

    uint32_t Classification::vectorRegisters() const
    {
        return static_cast<uint32_t>(std::ranges::count(classes, Class::Sse));
    }

    std::optional<Classification> classify(TaskContext& ctx, const TypeInfo& type)
    {
        const uint64_t size = type.sizeOf(ctx);
        if (size > UINT32_MAX)
            return std::nullopt;
        Classification result;
        result.size = static_cast<uint32_t>(size);
        result.alignment = std::max(type.alignOf(ctx), 1u);
        if (size > 16)
        {
            markMemory(result);
            return result;
        }
        if (!classifyField(ctx, result, type, 0))
            return std::nullopt;
        // A union can replace the first half of a vector with an INTEGER class.
        // Its remaining SSEUP half then starts a separate vector register.
        if (result.classes[1] == Class::SseUp && result.classes[0] != Class::Sse)
            result.classes[1] = Class::Sse;
        return result;
    }

    ArgumentLocation ArgumentAllocator::next(const Classification& type)
    {
        ArgumentLocation result;
        if (!type.size)
            return result;
        const uint32_t integers = type.integerRegisters();
        const uint32_t vectors = type.vectorRegisters();
        // A split aggregate is indivisible: failure in either bank leaves both
        // counters untouched, so later scalar arguments can still use those lanes.
        if (type.memory() || integers_ + integers > 6 || vectors_ + vectors > 8)
        {
            const uint32_t alignment = std::max(type.alignment, 8u);
            stackAlignment_ = std::max(stackAlignment_, alignment);
            stackSize_ = (stackSize_ + alignment - 1) / alignment * alignment;
            result.onStack = true;
            result.stackOffset = stackSize_;
            stackSize_ += (static_cast<uint64_t>(type.size) + 7) / 8 * 8;
            return result;
        }
        for (uint32_t part = 0; part < type.classes.size(); ++part)
        {
            switch (type.classes[part])
            {
                case Class::Integer:
                    result.registers[part] = static_cast<uint8_t>(integers_++);
                    break;
                case Class::Sse:
                    result.registers[part] = static_cast<uint8_t>(vectors_++);
                    break;
                case Class::SseUp:
                    SWC_ASSERT(part && type.classes[part - 1] == Class::Sse);
                    result.registers[part] = result.registers[part - 1];
                    break;
                case Class::None:
                    break;
                default:
                    SWC_UNREACHABLE();
            }
        }
        return result;
    }
}

SWC_END_NAMESPACE();
