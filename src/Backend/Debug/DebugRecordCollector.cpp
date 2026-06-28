#include "pch.h"
#include "Backend/Debug/DebugRecordCollector.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Compiler/Sema/Symbol/Symbol.Constant.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Module.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Support/Math/Hash.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Utf8 debugDataSymbolName(const TaskContext& ctx, const SymbolVariable& symbol)
    {
        Utf8 key = symbol.getFullScopedName(ctx);
        key += "|";
        key += std::to_string(symbol.tokRef().get());
        key += "|";
        key += std::to_string(symbol.offset());
        return std::format("__swc_dbg_data_{:08x}", Math::hash(key.view()));
    }

    bool shouldEmitDebugVariable(const TaskContext& ctx, const SymbolVariable& symbol)
    {
        if (!symbol.idRef().isValid() || symbol.typeRef().isInvalid())
            return false;
        if (symbol.hasExtraFlag(SymbolVariableFlagsE::RuntimeStorage))
            return false;
        return !symbol.name(ctx).empty();
    }

    bool shouldEmitDebugConstant(const TaskContext& ctx, const SymbolConstant& symbol)
    {
        if (!symbol.idRef().isValid() || symbol.typeRef().isInvalid() || symbol.cstRef().isInvalid())
            return false;
        return !symbol.name(ctx).empty();
    }

    Utf8 dataSectionName(const SymbolVariable& symbol)
    {
        switch (symbol.globalStorageKind())
        {
            case DataSegmentKind::GlobalInit:
                return ".data";
            case DataSegmentKind::GlobalZero:
                return ".bss";
            default:
                return {};
        }
    }

    void appendDebugConstantRecord(std::vector<DebugInfoConstantRecord>& out, const TaskContext& ctx, const SymbolConstant& symbol)
    {
        if (!shouldEmitDebugConstant(ctx, symbol))
            return;

        DebugInfoConstantRecord record;
        record.name        = Utf8(symbol.name(ctx));
        record.linkageName = symbol.getFullScopedName(ctx);
        record.typeRef     = symbol.typeRef();
        record.isConst     = true;
        record.valueRef    = symbol.cstRef();
        out.push_back(record);
    }

    void collectGlobalDebugConstantsRec(std::vector<DebugInfoConstantRecord>& out, const TaskContext& ctx, const SymbolMap& symbolMap)
    {
        std::vector<const Symbol*> symbols;
        symbolMap.getAllSymbols(symbols);
        for (const Symbol* symbol : symbols)
        {
            SWC_ASSERT(symbol != nullptr);

            if (const auto* constant = symbol->safeCast<SymbolConstant>())
            {
                appendDebugConstantRecord(out, ctx, *constant);
                continue;
            }

            if (!symbol->isModule() && !symbol->isNamespace())
                continue;

            collectGlobalDebugConstantsRec(out, ctx, *symbol->asSymMap());
        }
    }

    void collectGlobalDebugConstants(std::vector<DebugInfoConstantRecord>& out, const TaskContext& ctx, const CompilerInstance& compiler)
    {
        if (const SymbolModule* rootModule = compiler.symModule())
            collectGlobalDebugConstantsRec(out, ctx, *rootModule);

        for (const SourceFile* file : compiler.files())
        {
            if (!file)
                continue;
            if (const SymbolNamespace* fileNamespace = file->fileNamespace())
                collectGlobalDebugConstantsRec(out, ctx, *fileNamespace);
        }
    }

    void collectFunctionDebugConstants(std::vector<DebugInfoConstantRecord>& out, const TaskContext& ctx, const SymbolFunction& function)
    {
        std::vector<const Symbol*> symbols;
        function.getAllSymbols(symbols);
        for (const Symbol* symbol : symbols)
        {
            SWC_ASSERT(symbol != nullptr);
            if (const auto* constant = symbol->safeCast<SymbolConstant>())
                appendDebugConstantRecord(out, ctx, *constant);
        }
    }

    const SourceFile* functionSourceFile(const NativeBackendBuilder& builder, const NativeFunctionInfo& info)
    {
        if (!info.symbol || !info.symbol->decl())
            return nullptr;

        const SourceViewRef srcViewRef = info.symbol->srcViewRef();
        if (!builder.compiler().hasSourceView(srcViewRef))
            return nullptr;

        return builder.compiler().owningSourceFile(builder.compiler().srcView(srcViewRef));
    }

    void collectFunction(NativeBackendBuilder& builder, const NativeFunctionInfo& info, CollectedDebugRecords& out)
    {
        out.functionStorage.emplace_back();
        FunctionDebugStorage& storage          = out.functionStorage.back();
        const MicroReg        parameterBaseReg = info.symbol ? CallConv::get(info.symbol->callConvKind()).stackPointer : MicroReg::invalid();
        const MicroReg        localBaseReg     = info.symbol ? info.symbol->debugStackBaseReg() : MicroReg::invalid();

        if (info.symbol)
        {
            for (const SymbolVariable* symVar : info.symbol->parameters())
            {
                SWC_ASSERT(symVar != nullptr);
                if (!symVar->debugStackSlotSize())
                    continue;
                if (!shouldEmitDebugVariable(builder.ctx(), *symVar))
                    continue;

                DebugInfoLocalRecord record;
                record.name        = Utf8(symVar->name(builder.ctx()));
                record.linkageName = symVar->getFullScopedName(builder.ctx());
                record.typeRef     = symVar->typeRef();
                record.isConst     = symVar->hasExtraFlag(SymbolVariableFlagsE::Let);
                record.offset      = symVar->debugStackSlotOffset();
                // Parameters are spilled to their debug home relative to the local-stack base
                // register (see spillParametersToDebugSlots), the same base locals use -- not raw
                // SP, which moves during the body. Record that base so the debugger reads the
                // right slot.
                record.baseReg = localBaseReg;
                storage.parameters.push_back(record);
            }

            for (const SymbolVariable* symVar : info.symbol->localVariables())
            {
                SWC_ASSERT(symVar != nullptr);
                if (!symVar->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
                    continue;
                if (!shouldEmitDebugVariable(builder.ctx(), *symVar))
                    continue;

                DebugInfoLocalRecord record;
                record.name        = Utf8(symVar->name(builder.ctx()));
                record.linkageName = symVar->getFullScopedName(builder.ctx());
                record.typeRef     = symVar->typeRef();
                record.isConst     = symVar->hasExtraFlag(SymbolVariableFlagsE::Let);
                record.offset      = symVar->offset();
                record.baseReg     = localBaseReg;
                storage.locals.push_back(record);
            }

            collectFunctionDebugConstants(storage.constants, builder.ctx(), *info.symbol);
        }

        out.functions.push_back({.symbolName    = info.symbolName,
                                 .debugName     = info.debugName,
                                 .returnTypeRef = info.symbol ? info.symbol->returnTypeRef() : TypeRef::invalid(),
                                 .machineCode   = info.machineCode,
                                 .sourceFile    = functionSourceFile(builder, info),
                                 .frameSize     = info.symbol ? info.symbol->debugStackFrameSize() : 0,
                                 .frameBaseReg  = parameterBaseReg,
                                 .parameters    = storage.parameters,
                                 .locals        = storage.locals,
                                 .constants     = storage.constants});
    }
}

void collectDebugRecords(NativeBackendBuilder&                      builder,
                         std::span<const NativeFunctionInfo* const> functions,
                         const NativeStartupInfo*                   startup,
                         const bool                                 includeData,
                         CollectedDebugRecords&                     out)
{
    // Reserve so DebugInfoFunctionRecord's spans into functionStorage stay valid as we append.
    out.functionStorage.reserve(functions.size());
    out.functions.reserve(functions.size() + (startup ? 1 : 0));

    if (startup)
        out.functions.push_back({.symbolName = startup->symbolName, .debugName = startup->debugName, .returnTypeRef = TypeRef::invalid(), .machineCode = &startup->code});

    for (const NativeFunctionInfo* info : functions)
    {
        if (!info)
            continue;
        collectFunction(builder, *info, out);
    }

    if (includeData)
    {
        out.globals.reserve(builder.regularGlobals.size());
        for (const SymbolVariable* symbol : builder.regularGlobals)
        {
            SWC_ASSERT(symbol != nullptr);
            if (!symbol->hasGlobalStorage())
                continue;
            if (!shouldEmitDebugVariable(builder.ctx(), *symbol))
                continue;

            const Utf8 sectionName = dataSectionName(*symbol);
            if (sectionName.empty())
                continue;

            DebugInfoDataRecord record;
            record.name         = Utf8(symbol->name(builder.ctx()));
            record.linkageName  = symbol->getFullScopedName(builder.ctx());
            record.typeRef      = symbol->typeRef();
            record.isConst      = symbol->hasExtraFlag(SymbolVariableFlagsE::Let);
            record.symbolName   = debugDataSymbolName(builder.ctx(), *symbol);
            record.sectionName  = sectionName;
            record.symbolOffset = symbol->offset();
            record.isGlobal     = symbol->isPublic();
            out.globals.push_back(record);
        }

        collectGlobalDebugConstants(out.constants, builder.ctx(), builder.compiler());
    }
}

SWC_END_NAMESPACE();
