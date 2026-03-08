#include "pch.h"
#include "Main/Stats.h"
#include "Main/Global.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

void Stats::print(const TaskContext& ctx) const
{
    const Logger::ScopedLock loggerLock(ctx.global().logger());

    constexpr auto colorHeader = LogColor::Yellow;
    constexpr auto colorMsg    = LogColor::White;

    Logger::printHeaderDot(ctx, colorHeader, "numWorkers", colorMsg, Utf8Helper::toNiceBigNumber(ctx.global().jobMgr().numWorkers()));
    Logger::printHeaderDot(ctx, colorHeader, "timeTotal", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeTotal.load())));
    Logger::printHeaderDot(ctx, colorHeader, "osMaxAllocated", colorMsg, Utf8Helper::toNiceSize(Os::peakProcessMemoryUsage()));

#if SWC_HAS_STATS
    // Frontend counts
    Logger::print(ctx, "\n");
    Logger::printHeaderDot(ctx, colorHeader, "count.frontend.numFiles", colorMsg, Utf8Helper::toNiceBigNumber(numFiles.load()));
    Logger::printHeaderDot(ctx, colorHeader, "count.frontend.numTokens", colorMsg, Utf8Helper::toNiceBigNumber(numTokens.load()));
    Logger::printHeaderDot(ctx, colorHeader, "count.frontend.numAstNodes", colorMsg, Utf8Helper::toNiceBigNumber(numAstNodes.load()));
    Logger::printHeaderDot(ctx, colorHeader, "count.frontend.numVisitedAstNodes", colorMsg, Utf8Helper::toNiceBigNumber(numVisitedAstNodes.load()));

    // Semantic model counts
    Logger::print(ctx, "\n");
    Logger::printHeaderDot(ctx, colorHeader, "count.sema.numConstants", colorMsg, Utf8Helper::toNiceBigNumber(numConstants.load()));
    Logger::printHeaderDot(ctx, colorHeader, "count.sema.numTypes", colorMsg, Utf8Helper::toNiceBigNumber(numTypes.load()));
    Logger::printHeaderDot(ctx, colorHeader, "count.sema.numIdentifiers", colorMsg, Utf8Helper::toNiceBigNumber(numIdentifiers.load()));
    Logger::printHeaderDot(ctx, colorHeader, "count.sema.numSymbols", colorMsg, Utf8Helper::toNiceBigNumber(numSymbols.load()));
    Logger::printHeaderDot(ctx, colorHeader, "count.sema.numCodeGenFunctions", colorMsg, Utf8Helper::toNiceBigNumber(numCodeGenFunctions.load()));

    // Backend micro counts
    Logger::print(ctx, "\n");
    const size_t numMicroNoOptim = numMicroInstrNoOptim.load();
    const size_t numMicroFinal   = numMicroInstrFinal.load();
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.instrNoOptim", colorMsg, Utf8Helper::toNiceBigNumber(numMicroNoOptim));
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.instrFinal", colorMsg, Utf8Helper::toNiceBigNumber(numMicroFinal));

    const int64_t numMicroPipelineDelta     = static_cast<int64_t>(numMicroFinal) - static_cast<int64_t>(numMicroNoOptim);
    const char    numMicroPipelineDeltaSign = numMicroPipelineDelta >= 0 ? '+' : '-';
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.instrDelta", colorMsg, std::format("{}{}", numMicroPipelineDeltaSign, Utf8Helper::toNiceBigNumber(static_cast<size_t>(std::abs(numMicroPipelineDelta)))));

    double pipelineRemovedPct = 0.0;
    if (numMicroNoOptim != 0)
        pipelineRemovedPct = 100.0 * static_cast<double>(numMicroPipelineDelta) / static_cast<double>(numMicroNoOptim);
    Logger::printHeaderDot(ctx, colorHeader, "count.micro.instrReducedPct", colorMsg, std::format("{:.2f}%", pipelineRemovedPct));

    // Time
    Logger::print(ctx, "\n");
    Logger::printHeaderDot(ctx, colorHeader, "time.frontend.loadFile", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeLoadFile.load())));
    Logger::printHeaderDot(ctx, colorHeader, "time.frontend.lexer", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeLexer.load())));
    Logger::printHeaderDot(ctx, colorHeader, "time.frontend.parser", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeParser.load())));
    Logger::printHeaderDot(ctx, colorHeader, "time.sema.analysis", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeSema.load())));
    Logger::printHeaderDot(ctx, colorHeader, "time.backend.codegen", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeCodeGen.load())));
    Logger::printHeaderDot(ctx, colorHeader, "time.backend.microLower", colorMsg, Utf8Helper::toNiceTime(Timer::toSeconds(timeMicroLower.load())));

    struct MemoryStatLine
    {
        std::string_view name;
        size_t           value = 0;
    };

    const size_t memTotal                      = memMaxAllocated.load();
    const size_t memCurrent                    = memAllocated.load();
    const size_t memFrontendSourceValue        = memFrontendSource.load();
    const size_t memFrontendTokensValue        = memFrontendTokens.load();
    const size_t memFrontendLinesValue         = memFrontendLines.load();
    const size_t memFrontendTriviaValue        = memFrontendTrivia.load();
    const size_t memFrontendIdentifiersValue   = memFrontendIdentifiers.load();
    const size_t memFrontendAstReservedValue   = memFrontendAstReserved.load();
    const size_t memSemaSymbolsValue           = memSymbols.load();
    const size_t memSemaSymbolMapsValue        = memSymbolMaps.load();
    const size_t memSemaConstantsValue         = memConstants.load();
    const size_t memSemaConstantsReserved      = memConstantsReserved.load();
    const size_t memSemaTypesValue             = memTypes.load();
    const size_t memSemaTypesReserved          = memTypesReserved.load();
    const size_t memSemaNodePayloadValue       = memSemaNodePayloadReserved.load();
    const size_t memSemaIdentifiersValue       = memSemaIdentifiersReserved.load();
    const size_t memCompilerArenaValue         = memCompilerArenaReserved.load();
    const size_t memJitReservedValue           = memJitReserved.load();
    const size_t memMicroStorageFinalValue     = memMicroStorageFinal.load();
    const size_t memDataSegmentConstantValue   = memDataSegmentConstant.load();
    const size_t memDataSegmentGlobalZeroValue = memDataSegmentGlobalZero.load();
    const size_t memDataSegmentGlobalInitValue = memDataSegmentGlobalInit.load();
    const size_t memDataSegmentCompilerValue   = memDataSegmentCompiler.load();

    const size_t frontendTotalKnown = memFrontendSourceValue +
                                      memFrontendTokensValue +
                                      memFrontendLinesValue +
                                      memFrontendTriviaValue +
                                      memFrontendIdentifiersValue +
                                      memFrontendAstReservedValue;
    const size_t semaTotalKnown = memSemaSymbolsValue +
                                  memSemaSymbolMapsValue +
                                  memSemaConstantsReserved +
                                  memSemaTypesReserved +
                                  memSemaNodePayloadValue +
                                  memSemaIdentifiersValue +
                                  memCompilerArenaValue +
                                  memDataSegmentConstantValue +
                                  memDataSegmentGlobalZeroValue +
                                  memDataSegmentGlobalInitValue +
                                  memDataSegmentCompilerValue;
    const size_t codegenTotalKnown = memJitReservedValue + memMicroStorageFinalValue;
    const size_t totalKnown        = frontendTotalKnown + semaTotalKnown + codegenTotalKnown;
    const size_t unknownPeak       = memTotal > totalKnown ? memTotal - totalKnown : 0;
    const size_t unknownCurrent    = memCurrent > totalKnown ? memCurrent - totalKnown : 0;
    const size_t unknownTransient  = memTotal > memCurrent ? memTotal - memCurrent : 0;

    std::vector<MemoryStatLine> memoryStageSums;
    memoryStageSums.push_back({.name = "mem.total", .value = memTotal});
    memoryStageSums.push_back({.name = "mem.current", .value = memCurrent});
    memoryStageSums.push_back({.name = "mem.totalKnown", .value = totalKnown});
    memoryStageSums.push_back({.name = "mem.untracked.peak", .value = unknownPeak});
    memoryStageSums.push_back({.name = "mem.untracked.current", .value = unknownCurrent});
    memoryStageSums.push_back({.name = "mem.untracked.transient", .value = unknownTransient});
    memoryStageSums.push_back({.name = "mem.frontend.totalKnown", .value = frontendTotalKnown});
    memoryStageSums.push_back({.name = "mem.sema.totalKnown", .value = semaTotalKnown});
    memoryStageSums.push_back({.name = "mem.codegen.totalKnown", .value = codegenTotalKnown});

    std::vector<MemoryStatLine> memoryDetails;
    memoryDetails.push_back({.name = "mem.frontend.source", .value = memFrontendSourceValue});
    memoryDetails.push_back({.name = "mem.frontend.tokens", .value = memFrontendTokensValue});
    memoryDetails.push_back({.name = "mem.frontend.lines", .value = memFrontendLinesValue});
    memoryDetails.push_back({.name = "mem.frontend.trivia", .value = memFrontendTriviaValue});
    memoryDetails.push_back({.name = "mem.frontend.identifiers", .value = memFrontendIdentifiersValue});
    memoryDetails.push_back({.name = "mem.frontend.ast", .value = memFrontendAstReservedValue});
    memoryDetails.push_back({.name = "mem.sema.symbols", .value = memSemaSymbolsValue});
    memoryDetails.push_back({.name = "mem.sema.symbolMaps", .value = memSemaSymbolMapsValue});
    memoryDetails.push_back({.name = "mem.sema.constants", .value = memSemaConstantsValue});
    memoryDetails.push_back({.name = "mem.sema.constantsStorage", .value = memSemaConstantsReserved});
    memoryDetails.push_back({.name = "mem.sema.types", .value = memSemaTypesValue});
    memoryDetails.push_back({.name = "mem.sema.typesStorage", .value = memSemaTypesReserved});
    memoryDetails.push_back({.name = "mem.sema.nodePayload", .value = memSemaNodePayloadValue});
    memoryDetails.push_back({.name = "mem.sema.identifiers", .value = memSemaIdentifiersValue});
    memoryDetails.push_back({.name = "mem.compiler.arena", .value = memCompilerArenaValue});
    memoryDetails.push_back({.name = "mem.compiler.dataSegmentConstant", .value = memDataSegmentConstantValue});
    memoryDetails.push_back({.name = "mem.compiler.dataSegmentGlobalZero", .value = memDataSegmentGlobalZeroValue});
    memoryDetails.push_back({.name = "mem.compiler.dataSegmentGlobalInit", .value = memDataSegmentGlobalInitValue});
    memoryDetails.push_back({.name = "mem.compiler.dataSegmentCompiler", .value = memDataSegmentCompilerValue});
    memoryDetails.push_back({.name = "mem.jit.reserved", .value = memJitReservedValue});
    memoryDetails.push_back({.name = "mem.micro.storageFinal", .value = memMicroStorageFinalValue});

    std::ranges::sort(memoryDetails, [](const MemoryStatLine& lhs, const MemoryStatLine& rhs) {
        return lhs.value > rhs.value;
    });

    Logger::print(ctx, "\n");
    for (const MemoryStatLine& memoryStat : memoryStageSums)
        Logger::printHeaderDot(ctx, colorHeader, memoryStat.name, colorMsg, Utf8Helper::toNiceSize(memoryStat.value));

    Logger::print(ctx, "\n");
    for (const MemoryStatLine& memoryStat : memoryDetails)
        Logger::printHeaderDot(ctx, colorHeader, memoryStat.name, colorMsg, Utf8Helper::toNiceSize(memoryStat.value));
#endif

    Logger::print(ctx, "\n");
}

SWC_END_NAMESPACE();
