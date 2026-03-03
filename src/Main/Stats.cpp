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
    Logger::printHeaderDot(ctx, colorHeader, "maxAllocated", colorMsg, Utf8Helper::toNiceSize(Os::peakProcessMemoryUsage()));

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

    std::vector<MemoryStatLine> memoryStats;
    memoryStats.push_back({.name = "mem.process.maxAllocated", .value = memMaxAllocated.load()});
    const size_t frontendTotalKnown = memFrontendSource.load() +
                                      memFrontendTokens.load() +
                                      memFrontendLines.load() +
                                      memFrontendTrivia.load() +
                                      memFrontendIdentifiers.load() +
                                      memFrontendAstReserved.load();
    const size_t semaTotalKnown = memSymbols.load() +
                                  memConstants.load() +
                                  memTypes.load() +
                                  memSemaNodePayloadReserved.load() +
                                  memSemaIdentifiersReserved.load() +
                                  memCompilerArenaReserved.load();
    const size_t backendTotalKnown = memJitReserved.load() + memMicroStorageFinal.load();

    memoryStats.push_back({.name = "mem.frontend.totalKnown", .value = frontendTotalKnown});
    memoryStats.push_back({.name = "mem.sema.totalKnown", .value = semaTotalKnown});
    memoryStats.push_back({.name = "mem.backend.totalKnown", .value = backendTotalKnown});
    memoryStats.push_back({.name = "mem.sema.symbols", .value = memSymbols.load()});
    memoryStats.push_back({.name = "mem.compiler.arena.reserved", .value = memCompilerArenaReserved.load()});
    memoryStats.push_back({.name = "mem.frontend.ast.reserved", .value = memFrontendAstReserved.load()});
    memoryStats.push_back({.name = "mem.frontend.tokens", .value = memFrontendTokens.load()});
    memoryStats.push_back({.name = "mem.jit.reserved", .value = memJitReserved.load()});
    memoryStats.push_back({.name = "mem.micro.storageFinal", .value = memMicroStorageFinal.load()});
    memoryStats.push_back({.name = "mem.sema.nodePayload.reserved", .value = memSemaNodePayloadReserved.load()});

    std::ranges::sort(memoryStats, [](const MemoryStatLine& lhs, const MemoryStatLine& rhs) {
        return lhs.value > rhs.value;
    });

    Logger::print(ctx, "\n");
    for (const MemoryStatLine& memoryStat : memoryStats)
        Logger::printHeaderDot(ctx, colorHeader, memoryStat.name, colorMsg, Utf8Helper::toNiceSize(memoryStat.value));
#endif

    Logger::print(ctx, "\n");
}

SWC_END_NAMESPACE();
