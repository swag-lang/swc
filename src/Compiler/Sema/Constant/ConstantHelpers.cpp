#include "pch.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

ConstantRef ConstantHelpers::makeSourceCodeLocation(Sema& sema, const SourceCodeRange& codeRange)
{
    const TaskContext& ctx      = sema.ctx();
    const TypeRef      typeRef  = sema.typeMgr().structSourceCodeLocation();
    const SourceView*  srcView  = codeRange.srcView;
    const SourceFile*  file     = srcView ? srcView->file() : nullptr;
    const Utf8         fileName = file ? Utf8(file->path().string()) : Utf8{};

    const uint32_t shardIndex = std::hash<std::string_view>{}(fileName.view()) & (ConstantManager::SHARD_COUNT - 1);
    DataSegment&   segment    = sema.cstMgr().shardDataSegment(shardIndex);

    const auto [offset, storage] = segment.reserveBytes(sizeof(Runtime::SourceCodeLocation), alignof(Runtime::SourceCodeLocation), true);
    auto* const rtLoc            = reinterpret_cast<Runtime::SourceCodeLocation*>(storage);

    rtLoc->fileName.length = segment.addString(offset, offsetof(Runtime::SourceCodeLocation, fileName.ptr), fileName);

    rtLoc->funcName.ptr    = nullptr;
    rtLoc->funcName.length = 0;

    rtLoc->lineStart = codeRange.line;
    rtLoc->colStart  = codeRange.column;
    rtLoc->lineEnd   = codeRange.line;
    rtLoc->colEnd    = codeRange.column + codeRange.len;

    const auto          bytes  = ByteSpan{storage, sizeof(Runtime::SourceCodeLocation)};
    const ConstantValue cstVal = ConstantValue::makeStructBorrowed(ctx, typeRef, bytes);
    return sema.cstMgr().addConstant(ctx, cstVal);
}

ConstantRef ConstantHelpers::makeSourceCodeLocation(Sema& sema, const AstNode& node)
{
    const SourceCodeRange codeRange = node.codeRangeWithChildren(sema.ctx(), sema.ast());
    return makeSourceCodeLocation(sema, codeRange);
}

SWC_END_NAMESPACE();
