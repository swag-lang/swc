#include "pch.h"
#include "Sema/Type/TypeGen.h"
#include "Core/DataSegment.h"
#include "Main/TaskContext.h"
#include "Runtime/Runtime.h"
#include "Sema/Core/Sema.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef selectTypeInfoStructType(const TypeManager& tm, const TypeInfo& type)
    {
        if (type.isBool() || type.isInt() || type.isFloat() || type.isString() || type.isRune() || type.isAny() || type.isVoid())
            return tm.structTypeInfoNative();
        if (type.isEnum())
            return tm.structTypeInfoEnum();
        if (type.isArray())
            return tm.structTypeInfoArray();
        if (type.isSlice())
            return tm.structTypeInfoSlice();
        if (type.isPointerLike())
            return tm.structTypeInfoPointer();
        if (type.isStruct())
            return tm.structTypeInfoStruct();
        return tm.structTypeInfo();
    }

    Result ensureTypeInfoStructReady(Sema& sema, const TypeManager& tm, const TypeRef structTypeRef, const AstNode& node)
    {
        if (structTypeRef.isInvalid())
            return sema.waitIdentifier(sema.idMgr().nameTypeInfo(), node.srcViewRef(), node.tokRef());

        const auto& structType = tm.get(structTypeRef);
        if (!structType.isCompleted(sema.ctx()))
            return sema.waitCompleted(&structType.symStruct(), node.srcViewRef(), node.tokRef());

        return Result::Continue;
    }

    void addFlag(Runtime::TypeInfo& rt, Runtime::TypeInfoFlags f)
    {
        rt.flags = static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rt.flags) | static_cast<uint32_t>(f));
    }

    void initCommon(Runtime::TypeInfo&      rt,
                    const TypeInfo&         type,
                    const TypeManager&      tm,
                    Sema&                   sema,
                    DataSegment&            storage,
                    uint32_t                offset,
                    TypeGen::TypeGenResult& result)
    {
        auto& ctx = sema.ctx();

        const Utf8 name     = type.toName(ctx);
        const Utf8 fullname = name;

        rt.sizeofType = static_cast<uint32_t>(type.sizeOf(ctx));
        rt.crc        = type.hash();
        rt.flags      = Runtime::TypeInfoFlags::Zero;

        if (type.isConst())
            addFlag(rt, Runtime::TypeInfoFlags::Const);
        if (type.isNullable())
            addFlag(rt, Runtime::TypeInfoFlags::Nullable);

        const auto& structType = tm.get(result.structTypeRef);
        result.view            = std::string_view{storage.ptr<char>(offset), structType.sizeOf(ctx)};

        rt.fullname.length = storage.addString(offset, offsetof(Runtime::TypeInfo, fullname.ptr), fullname);
        rt.name.length     = storage.addString(offset, offsetof(Runtime::TypeInfo, name.ptr), name);

        if (type.isStruct())
        {
            auto* rs              = storage.ptr<Runtime::TypeInfoStruct>(offset);
            rs->structName.length = storage.addString(offset, offsetof(Runtime::TypeInfoStruct, structName.ptr), name);
        }
    }

    void initNativeKind(Runtime::TypeInfoNative& n, const TypeInfo& type)
    {
        n.base.kind  = Runtime::TypeInfoKind::Native;
        n.nativeKind = Runtime::TypeInfoNativeKind::Void;

        if (type.isBool())
        {
            n.nativeKind = Runtime::TypeInfoNativeKind::Bool;
            return;
        }

        if (type.isInt())
        {
            addFlag(n.base, Runtime::TypeInfoFlags::Integer);
            if (type.isIntUnsigned())
                addFlag(n.base, Runtime::TypeInfoFlags::Unsigned);

            switch (type.intBits())
            {
                case 8: n.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U8 : Runtime::TypeInfoNativeKind::S8; break;
                case 16: n.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U16 : Runtime::TypeInfoNativeKind::S16; break;
                case 32: n.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U32 : Runtime::TypeInfoNativeKind::S32; break;
                case 64: n.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U64 : Runtime::TypeInfoNativeKind::S64; break;
            }
            return;
        }

        if (type.isFloat())
        {
            addFlag(n.base, Runtime::TypeInfoFlags::Float);
            n.nativeKind = (type.floatBits() == 32) ? Runtime::TypeInfoNativeKind::F32 : Runtime::TypeInfoNativeKind::F64;
            return;
        }

        if (type.isString())
        {
            n.nativeKind = Runtime::TypeInfoNativeKind::String;
            return;
        }

        if (type.isRune())
        {
            n.nativeKind = Runtime::TypeInfoNativeKind::Rune;
            return;
        }

        if (type.isAny())
        {
            n.nativeKind = Runtime::TypeInfoNativeKind::Any;
            return;
        }

        if (type.isVoid())
        {
            n.nativeKind = Runtime::TypeInfoNativeKind::Void;
            return;
        }
    }

    void initArray(Runtime::TypeInfoArray& a, const TypeInfo& type)
    {
        a.base.kind = Runtime::TypeInfoKind::Array;

        const auto& dims = type.arrayDims();
        a.count          = dims.empty() ? 0 : dims[0];
        a.totalCount     = dims.empty() ? 0 : dims[0];
        for (size_t i = 1; i < dims.size(); i++)
            a.totalCount *= dims[i];
    }
}

Result TypeGen::makeTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenResult& result)
{
    auto&              ctx  = sema.ctx();
    const TypeManager& tm   = ctx.typeMgr();
    const TypeInfo&    type = tm.get(typeRef);
    const AstNode&     node = sema.node(ownerNodeRef);

    // Pick and validate the "TypeInfo struct" layout used to serialize this type
    result.structTypeRef = selectTypeInfoStructType(tm, type);
    RESULT_VERIFY(ensureTypeInfoStructReady(sema, tm, result.structTypeRef, node));

    // Allocate the correct runtime TypeInfo payload
    uint32_t           offset = 0;
    Runtime::TypeInfo* rt     = nullptr;

    if (result.structTypeRef == tm.structTypeInfoNative())
    {
        Runtime::TypeInfoNative* n;
        offset = storage.reserve(&n);
        rt     = &n->base;
        initNativeKind(*n, type);
    }
    else if (result.structTypeRef == tm.structTypeInfoEnum())
    {
        Runtime::TypeInfoEnum* e;
        offset       = storage.reserve(&e);
        rt           = &e->base;
        e->base.kind = Runtime::TypeInfoKind::Enum;
    }
    else if (result.structTypeRef == tm.structTypeInfoArray())
    {
        Runtime::TypeInfoArray* a;
        offset = storage.reserve(&a);
        rt     = &a->base;
        initArray(*a, type);
    }
    else if (result.structTypeRef == tm.structTypeInfoSlice())
    {
        Runtime::TypeInfoSlice* s;
        offset       = storage.reserve(&s);
        rt           = &s->base;
        s->base.kind = Runtime::TypeInfoKind::Slice;
    }
    else if (result.structTypeRef == tm.structTypeInfoPointer())
    {
        Runtime::TypeInfoPointer* p;
        offset       = storage.reserve(&p);
        rt           = &p->base;
        p->base.kind = Runtime::TypeInfoKind::Pointer;
    }
    else if (result.structTypeRef == tm.structTypeInfoStruct())
    {
        Runtime::TypeInfoStruct* s;
        offset       = storage.reserve(&s);
        rt           = &s->base;
        s->base.kind = Runtime::TypeInfoKind::Struct;
    }
    else
    {
        offset = storage.reserve(&rt);
    }

    // Fill common fields + strings + view
    initCommon(*rt, type, tm, sema, storage, offset, result);
    return Result::Continue;
}

SWC_END_NAMESPACE();
