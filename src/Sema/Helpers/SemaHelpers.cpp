#include "pch.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Lexer/SourceCodeLocation.h"
#include "Lexer/SourceView.h"
#include "Runtime/Runtime.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbol.Attribute.h"
#include "Sema/Symbol/Symbol.Function.h"
#include "Sema/Symbol/Symbol.Interface.h"
#include "Sema/Type/TypeManager.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE();

void SemaHelpers::handleSymbolRegistration(Sema& sema, SymbolMap* symbolMap, Symbol* sym)
{
    if (sym->isVariable())
    {
        if (const auto symStruct = symbolMap->safeCast<SymbolStruct>())
            symStruct->addField(reinterpret_cast<SymbolVariable*>(sym));

        if (sema.curScope().isParameters())
        {
            if (const auto symAttr = symbolMap->safeCast<SymbolAttribute>())
                symAttr->addParameter(reinterpret_cast<SymbolVariable*>(sym));
            if (const auto symFunc = symbolMap->safeCast<SymbolFunction>())
                symFunc->addParameter(reinterpret_cast<SymbolVariable*>(sym));
        }
    }

    if (sym->isFunction())
    {
        if (const auto symInterface = symbolMap->safeCast<SymbolInterface>())
            symInterface->addMethod(reinterpret_cast<SymbolFunction*>(sym));
    }
}

ConstantRef SemaHelpers::makeConstantLocation(Sema& sema, const AstNode& node)
{
    const auto& ctx     = sema.ctx();
    const auto  loc     = node.locationWithChildren(ctx, sema.ast());
    const auto  typeRef = sema.typeMgr().structSourceCodeLocation();

    Runtime::SourceCodeLocation rtLoc;

    const std::string_view nameView = sema.cstMgr().addString(ctx, loc.srcView->file()->path().string());
    rtLoc.fileName.ptr              = nameView.data();
    rtLoc.fileName.length           = nameView.size();

    rtLoc.funcName.ptr    = nullptr;
    rtLoc.funcName.length = 0;

    rtLoc.lineStart = loc.line;
    rtLoc.colStart  = loc.column;
    rtLoc.lineEnd   = loc.line;
    rtLoc.colEnd    = loc.column + loc.len;

    const auto view   = std::string_view(reinterpret_cast<const char*>(&rtLoc), sizeof(rtLoc));
    const auto cstVal = ConstantValue::makeStruct(ctx, typeRef, view);
    return sema.cstMgr().addConstant(ctx, cstVal);
}

ConstantRef SemaHelpers::makeConstantTypeInfo(Sema& sema, TypeRef typeRef)
{
    auto&       ctx     = sema.ctx();
    const auto& typeMgr = sema.typeMgr();
    const auto& type    = typeMgr.get(typeRef);

    Runtime::TypeInfo rtType;
    const Utf8        fullname    = type.toName(ctx);
    const Utf8        name        = type.toFamily(ctx);
    const auto        cstFullname = ConstantValue::makeString(ctx, fullname);
    const auto        cstName     = ConstantValue::makeString(ctx, name);
    rtType.fullname.ptr           = cstFullname.getString().data();
    rtType.fullname.length        = cstFullname.getString().size();
    rtType.name.ptr               = cstName.getString().data();
    rtType.name.length            = cstName.getString().size();
    rtType.sizeofType             = static_cast<uint32_t>(type.sizeOf(ctx));
    rtType.crc                    = type.hash();
    rtType.flags                  = Runtime::TypeInfoFlags::Zero;
    if (type.isConst())
        rtType.flags = static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rtType.flags) | static_cast<uint32_t>(Runtime::TypeInfoFlags::Const));
    if (type.isNullable())
        rtType.flags = static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rtType.flags) | static_cast<uint32_t>(Runtime::TypeInfoFlags::Nullable));

    if (type.isBool())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.nativeKind = Runtime::TypeInfoNativeKind::Bool;
        const auto view     = std::string_view(reinterpret_cast<const char*>(&rtNative), sizeof(rtNative));
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeMgr.structTypeInfoNative(), view));
    }

    if (type.isInt())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base      = rtType;
        rtNative.base.kind = Runtime::TypeInfoKind::Native;
        rtNative.base.flags =
            static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rtNative.base.flags) | static_cast<uint32_t>(Runtime::TypeInfoFlags::Integer));
        if (type.isIntUnsigned())
            rtNative.base.flags =
                static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rtNative.base.flags) | static_cast<uint32_t>(Runtime::TypeInfoFlags::Unsigned));

        switch (type.intBits())
        {
            case 8:
                rtNative.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U8 : Runtime::TypeInfoNativeKind::S8;
                break;
            case 16:
                rtNative.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U16 : Runtime::TypeInfoNativeKind::S16;
                break;
            case 32:
                rtNative.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U32 : Runtime::TypeInfoNativeKind::S32;
                break;
            case 64:
                rtNative.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U64 : Runtime::TypeInfoNativeKind::S64;
                break;
            default:
                rtNative.nativeKind = Runtime::TypeInfoNativeKind::Void;
                break;
        }

        const auto view = std::string_view(reinterpret_cast<const char*>(&rtNative), sizeof(rtNative));
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeMgr.structTypeInfoNative(), view));
    }

    if (type.isFloat())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.base.flags = static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rtNative.base.flags) | static_cast<uint32_t>(Runtime::TypeInfoFlags::Float));
        rtNative.nativeKind = type.floatBits() == 32 ? Runtime::TypeInfoNativeKind::F32 : Runtime::TypeInfoNativeKind::F64;
        const auto view     = std::string_view(reinterpret_cast<const char*>(&rtNative), sizeof(rtNative));
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeMgr.structTypeInfoNative(), view));
    }

    if (type.isString())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.nativeKind = Runtime::TypeInfoNativeKind::String;
        const auto view     = std::string_view(reinterpret_cast<const char*>(&rtNative), sizeof(rtNative));
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeMgr.structTypeInfoNative(), view));
    }

    if (type.isRune())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.nativeKind = Runtime::TypeInfoNativeKind::Rune;
        const auto view     = std::string_view(reinterpret_cast<const char*>(&rtNative), sizeof(rtNative));
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeMgr.structTypeInfoNative(), view));
    }

    if (type.isAny())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.nativeKind = Runtime::TypeInfoNativeKind::Any;
        const auto view     = std::string_view(reinterpret_cast<const char*>(&rtNative), sizeof(rtNative));
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeMgr.structTypeInfoNative(), view));
    }

    if (type.isVoid())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.nativeKind = Runtime::TypeInfoNativeKind::Void;
        const auto view     = std::string_view(reinterpret_cast<const char*>(&rtNative), sizeof(rtNative));
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeMgr.structTypeInfoNative(), view));
    }

    if (type.isEnum())
    {
        Runtime::TypeInfoEnum rtEnum;
        rtEnum.base       = rtType;
        rtEnum.base.kind  = Runtime::TypeInfoKind::Enum;
        rtEnum.rawType    = nullptr;
        rtEnum.values     = {nullptr, 0};
        rtEnum.attributes = {nullptr, 0};
        const auto view   = std::string_view(reinterpret_cast<const char*>(&rtEnum), sizeof(rtEnum));
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeMgr.structTypeInfoEnum(), view));
    }

    if (type.isArray())
    {
        Runtime::TypeInfoArray rtArray;
        rtArray.base       = rtType;
        rtArray.base.kind  = Runtime::TypeInfoKind::Array;
        rtArray.count      = type.arrayDims().empty() ? 0 : type.arrayDims()[0];
        rtArray.totalCount = type.arrayDims().empty() ? 0 : type.arrayDims()[0];
        for (size_t i = 1; i < type.arrayDims().size(); i++)
            rtArray.totalCount *= type.arrayDims()[i];
        rtArray.pointedType = nullptr;
        rtArray.finalType   = nullptr;
        const auto view     = std::string_view(reinterpret_cast<const char*>(&rtArray), sizeof(rtArray));
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeMgr.structTypeInfoArray(), view));
    }

    if (type.isSlice())
    {
        Runtime::TypeInfoSlice rtSlice;
        rtSlice.base        = rtType;
        rtSlice.base.kind   = Runtime::TypeInfoKind::Slice;
        rtSlice.pointedType = nullptr;
        const auto view     = std::string_view(reinterpret_cast<const char*>(&rtSlice), sizeof(rtSlice));
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeMgr.structTypeInfoSlice(), view));
    }

    if (type.isPointerLike())
    {
        Runtime::TypeInfoPointer rtPtr;
        rtPtr.base        = rtType;
        rtPtr.base.kind   = Runtime::TypeInfoKind::Pointer;
        rtPtr.pointedType = nullptr;
        const auto view   = std::string_view(reinterpret_cast<const char*>(&rtPtr), sizeof(rtPtr));
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeMgr.structTypeInfoPointer(), view));
    }

    if (type.isStruct())
    {
        Runtime::TypeInfoStruct rtStruct;
        rtStruct.base        = rtType;
        rtStruct.base.kind   = Runtime::TypeInfoKind::Struct;
        rtStruct.opInit      = nullptr;
        rtStruct.opDrop      = nullptr;
        rtStruct.opPostCopy  = nullptr;
        rtStruct.opPostMove  = nullptr;
        rtStruct.structName  = rtType.name;
        rtStruct.fields      = {nullptr, 0};
        rtStruct.usingFields = {nullptr, 0};
        rtStruct.methods     = {nullptr, 0};
        rtStruct.interfaces  = {nullptr, 0};
        rtStruct.generics    = {nullptr, 0};
        rtStruct.attributes  = {nullptr, 0};
        rtStruct.fromGeneric = nullptr;
        const auto view      = std::string_view(reinterpret_cast<const char*>(&rtStruct), sizeof(rtStruct));
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeMgr.structTypeInfoStruct(), view));
    }

    // Default to base TypeInfo if specialized one not found/implemented
    const auto view = std::string_view(reinterpret_cast<const char*>(&rtType), sizeof(rtType));
    return sema.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeMgr.structTypeInfo(), view));
}

Result SemaHelpers::extractConstantStructMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef)
{
    const std::string_view bytes = cst.getStruct();

    const TypeInfo& typeField = symVar.typeInfo(sema.ctx());
    SWC_ASSERT(symVar.offset() + typeField.sizeOf(sema.ctx()) <= bytes.size());
    const auto fieldBytes = std::string_view(bytes.data() + symVar.offset(), typeField.sizeOf(sema.ctx()));

    ConstantValue cv;
    if (typeField.isStruct())
    {
        cv = ConstantValue::makeStruct(sema.ctx(), typeField.typeRef(), fieldBytes);
    }
    else if (typeField.isBool())
    {
        cv = ConstantValue::makeBool(sema.ctx(), *reinterpret_cast<const bool*>(fieldBytes.data()));
    }
    else if (typeField.isIntLike())
    {
        const ApsInt apsInt(fieldBytes.data(), typeField.intLikeBits(), typeField.isIntUnsigned());
        cv = ConstantValue::makeFromIntLike(sema.ctx(), apsInt, typeField);
    }
    else if (typeField.isFloat())
    {
        const ApFloat apFloat(fieldBytes.data(), typeField.floatBits());
        cv = ConstantValue::makeFloat(sema.ctx(), apFloat, typeField.floatBits());
    }
    else if (typeField.isString())
    {
        const auto str = reinterpret_cast<const Runtime::String*>(fieldBytes.data());
        cv             = ConstantValue::makeString(sema.ctx(), std::string_view(str->ptr, str->length));
    }
    else
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_cst_struct_member_type, nodeMemberRef);
        diag.addArgument(Diagnostic::ARG_TYPE, symVar.typeRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    const auto cstRef = sema.cstMgr().addConstant(sema.ctx(), cv);
    sema.setConstant(nodeRef, cstRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
