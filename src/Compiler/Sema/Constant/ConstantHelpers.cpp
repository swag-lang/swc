#include "pch.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Runtime/Runtime.h"

SWC_BEGIN_NAMESPACE();

ConstantRef ConstantHelpers::makeSourceCodeLocation(Sema& sema, const SourceCodeRange& codeRange)
{
    auto&                 ctx       = sema.ctx();
    const TypeRef         typeRef   = sema.typeMgr().structSourceCodeLocation();

    Runtime::SourceCodeLocation rtLoc;

    const SourceView*     srcView  = codeRange.srcView;
    const SourceFile*     file     = srcView ? srcView->file() : nullptr;
    const std::string_view nameView = sema.cstMgr().addString(ctx, file ? file->path().string() : "");
    rtLoc.fileName.ptr              = nameView.data();
    rtLoc.fileName.length           = nameView.size();

    rtLoc.funcName.ptr    = nullptr;
    rtLoc.funcName.length = 0;

    rtLoc.lineStart = codeRange.line;
    rtLoc.colStart  = codeRange.column;
    rtLoc.lineEnd   = codeRange.line;
    rtLoc.colEnd    = codeRange.column + codeRange.len;

    const auto bytes  = ByteSpan{reinterpret_cast<const std::byte*>(&rtLoc), sizeof(rtLoc)};
    const auto cstVal = ConstantValue::makeStruct(ctx, typeRef, bytes);
    return sema.cstMgr().addConstant(ctx, cstVal);
}

ConstantRef ConstantHelpers::makeSourceCodeLocation(Sema& sema, const AstNode& node)
{
    const SourceCodeRange codeRange = node.codeRangeWithChildren(sema.ctx(), sema.ast());
    return makeSourceCodeLocation(sema, codeRange);
}

SWC_END_NAMESPACE();
