// The workloads of allocbench.swg, against mimalloc (built with USE_MIMALLOC) or the C runtime heap.
// Sizes, seeds, live-set shapes and touched bytes match the Swag program exactly.
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <malloc.h>
#include <string.h>
#include <psapi.h>

#ifdef USE_MIMALLOC
#include "mimalloc.h"
#define ALLOC(n) mi_malloc(n)
#define ALLOC_ALIGNED(n, a) mi_malloc_aligned(n, a)
#define FREE_ALIGNED(p) mi_free(p)
#define FREE(p) mi_free(p)
#define REALLOC(p, n) mi_realloc(p, n)
#else
#define ALLOC(n) malloc(n)
#define ALLOC_ALIGNED(n, a) _aligned_malloc(n, a)
#define FREE_ALIGNED(p) _aligned_free(p)
#define FREE(p) free(p)
#define REALLOC(p, n) realloc(p, n)
#endif

#define CHURN_SLOTS 50000
#define LARGE_SLOTS 32
#define MEDIUM_SLOTS 256
#define XFER_COUNT 2000000
#define XFER_RING 4096
#define HUGE_BYTES (32ull * 1024 * 1024)
#define HUGE_ROUNDS 200
#define SPREADREP_ROUNDS 10000
#define LATENCY_MAX_SAMPLES 4000000
#define LATENCY_BATCH 64

static LARGE_INTEGER clockFrequency;

static uint64_t ticks(void)
{
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    return (uint64_t)now.QuadPart;
}

/* The durations one worker records, in clock ticks, one per operation or per batch of operations. */
typedef struct
{
    uint32_t* samples;
    uint64_t  count;
    uint64_t  unit;
} Latency;

static void record(Latency* latency, uint64_t elapsed)
{
    if (latency->count < LATENCY_MAX_SAMPLES)
        latency->samples[latency->count++] = elapsed > UINT32_MAX ? UINT32_MAX : (uint32_t)elapsed;
}

static int compareSamples(const void* a, const void* b)
{
    uint32_t x = *(const uint32_t*)a, y = *(const uint32_t*)b;
    return x < y ? -1 : x > y;
}

/* The sample at 'rank' per thousand, in nanoseconds. */
static double percentile(Latency* latency, uint64_t rank)
{
    if (!latency->count)
        return 0;
    qsort(latency->samples, latency->count, sizeof(uint32_t), compareSamples);
    uint64_t index = latency->count * rank / 1000;
    if (index >= latency->count)
        index = latency->count - 1;
    return (double)latency->samples[index] * 1e9 / (double)clockFrequency.QuadPart;
}

static uint64_t next(uint64_t* state)
{
    uint64_t x = *state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *state = x;
    return x;
}

static uint64_t smallSize(uint64_t* state)
{
    uint64_t r = next(state);
    uint64_t k = r & 0xFF;
    if (k < 160)
        return 8 + ((r >> 8) & 63);
    if (k < 230)
        return 16 + ((r >> 8) & 255);
    if (k < 252)
        return 64 + ((r >> 8) & 2047);
    return 1024 + ((r >> 8) & 16383);
}

static uint64_t mediumSize(uint64_t* state) { return 4096 + next(state) % 61440; }
static uint64_t largeSize(uint64_t* state) { return 65536 + next(state) % (1024 * 1024 - 65536); }

typedef struct Node
{
    struct Node* left;
    struct Node* right;
} Node;

static Node* buildTree(int depth)
{
    Node* node  = (Node*)ALLOC(sizeof(Node));
    node->left  = depth > 0 ? buildTree(depth - 1) : NULL;
    node->right = depth > 0 ? buildTree(depth - 1) : NULL;
    return node;
}

static void freeTree(Node* node)
{
    if (node->left && node->right)
    {
        freeTree(node->left);
        freeTree(node->right);
    }
    FREE(node);
}

static void churn(uint64_t* state, uint64_t slots, uint64_t operations, uint64_t (*nextSize)(uint64_t*), int touchEveryPage, Latency* latency, int perOperation)
{
    char**    addresses = (char**)ALLOC(slots * sizeof(char*));
    uint64_t* sizes     = (uint64_t*)ALLOC(slots * sizeof(uint64_t));
    for (uint64_t i = 0; i < slots; i++)
    {
        sizes[i]     = nextSize(state);
        addresses[i] = (char*)ALLOC(sizes[i]);
    }

    uint64_t unit = perOperation ? 1 : LATENCY_BATCH;
    if (latency)
        latency->unit = unit;
    uint64_t start = latency ? ticks() : 0;
    for (uint64_t op = 0; op < operations; op++)
    {
        uint64_t i = next(state) % slots;
        FREE(addresses[i]);
        sizes[i]                 = nextSize(state);
        volatile char* block     = (char*)ALLOC(sizes[i]);
        block[0]                 = 1;
        block[sizes[i] - 1]      = 1;
        if (touchEveryPage)
        {
            for (uint64_t page = 0; page < sizes[i] / 4096; page++)
                block[page * 4096] = 1;
        }
        addresses[i] = (char*)block;
        if (latency && (op + 1) % unit == 0)
        {
            uint64_t now = ticks();
            record(latency, now - start);
            start = now;
        }
    }

    for (uint64_t i = 0; i < slots; i++)
        FREE(addresses[i]);
    FREE(addresses);
    FREE(sizes);
}

static const uint64_t spreadSizes[12] = {16, 48, 100, 200, 500, 1000, 3000, 6000, 12000, 20000, 40000, 60000};

static __declspec(noinline) uint64_t alignedBatches(uint64_t* state, Latency* latency)
{
    char* blocks[1024];
    if (latency)
        latency->unit = 1024;
    for (int round = 0; round < 10000; round++)
    {
        uint64_t start = latency ? ticks() : 0;
        for (int i = 0; i < 1024; i++)
        {
            const uint64_t size      = 1 + (next(state) & 4095);
            const size_t   alignment = (i & 1) == 0 ? 32 : 64;
            volatile char* block     = (char*)ALLOC_ALIGNED(size, alignment);
            block[0]                 = 1;
            block[size - 1]          = 1;
            blocks[i]                = (char*)block;
        }
        for (int i = 0; i < 1024; i++)
            FREE_ALIGNED(blocks[i]);
        if (latency)
            record(latency, ticks() - start);
    }
    return 10000 * 1024;
}

/* Ten live blocks of each of twelve sizes, allocated then freed: what 'spread' does once and 'spreadrep' repeats. */
static uint64_t spreadBody(void)
{
    char* addresses[120];
    for (int i = 0; i < 120; i++)
    {
        addresses[i]    = (char*)ALLOC(spreadSizes[i / 10]);
        addresses[i][0] = 1;
    }
    for (int i = 0; i < 120; i++)
        FREE(addresses[i]);
    return 120;
}

static uint64_t workingSet(void)
{
    PROCESS_MEMORY_COUNTERS counters;
    counters.cb = sizeof(counters);
    GetProcessMemoryInfo(GetCurrentProcess(), &counters, counters.cb);
    return counters.WorkingSetSize;
}

/* The churn, medium and large live sets allocated at once and freed, then the process working set at
   once, after the purge delay has passed and an allocation has run, and after the allocator trimmed. */
static void retain(uint64_t* state, uint64_t* idle, uint64_t* purged, uint64_t* trimmed)
{
    const uint64_t smallCount = 50000;
    char**         smallBlocks = (char**)ALLOC(smallCount * sizeof(char*));
    char*          mediumBlocks[MEDIUM_SLOTS];
    char*          largeBlocks[LARGE_SLOTS];
    for (uint64_t i = 0; i < smallCount; i++)
    {
        smallBlocks[i]    = (char*)ALLOC(smallSize(state));
        smallBlocks[i][0] = 1;
    }
    for (int i = 0; i < MEDIUM_SLOTS; i++)
    {
        uint64_t size   = mediumSize(state);
        mediumBlocks[i] = (char*)ALLOC(size);
        for (uint64_t page = 0; page < size / 4096; page++)
            mediumBlocks[i][page * 4096] = 1;
    }
    for (int i = 0; i < LARGE_SLOTS; i++)
    {
        uint64_t size  = largeSize(state);
        largeBlocks[i] = (char*)ALLOC(size);
        for (uint64_t page = 0; page < size / 4096; page++)
            largeBlocks[i][page * 4096] = 1;
    }
    for (uint64_t i = 0; i < smallCount; i++)
        FREE(smallBlocks[i]);
    for (int i = 0; i < MEDIUM_SLOTS; i++)
        FREE(mediumBlocks[i]);
    for (int i = 0; i < LARGE_SLOTS; i++)
        FREE(largeBlocks[i]);
    FREE(smallBlocks);

    *idle = workingSet();
    Sleep(700);
    FREE(ALLOC(1024 * 1024));
    *purged = workingSet();
#ifdef USE_MIMALLOC
    mi_collect(1);
#endif
    *trimmed = workingSet();
}

static uint64_t run(int workload, uint64_t seed, Latency* latency)
{
    uint64_t state = seed;
    switch (workload)
    {
    case 0:
    {
        if (latency)
            latency->unit = LATENCY_BATCH;
        uint64_t start = latency ? ticks() : 0;
        for (int i = 0; i < 20000000; i++)
        {
            volatile char* block = (char*)ALLOC(32);
            block[0]             = 1;
            FREE((void*)block);
            if (latency && (uint64_t)(i + 1) % LATENCY_BATCH == 0)
            {
                uint64_t now = ticks();
                record(latency, now - start);
                start = now;
            }
        }
        return 20000000;
    }
    case 1:
        for (int i = 0; i < 40; i++)
            freeTree(buildTree(14));
        return 40 * (1 << 15);
    case 9:
        return alignedBatches(&state, latency);
    case 10:
        if (latency)
            latency->unit = 1;
        for (int i = 0; i < HUGE_ROUNDS; i++)
        {
            uint64_t start = latency ? ticks() : 0;
            char*    block = (char*)ALLOC(HUGE_BYTES);
            for (uint64_t page = 0; page < HUGE_BYTES / 4096; page++)
                block[page * 4096] = 1;
            FREE(block);
            if (latency)
                record(latency, ticks() - start);
        }
        return HUGE_ROUNDS;
    case 11:
    {
        uint64_t operations = 0;
        for (int i = 0; i < SPREADREP_ROUNDS; i++)
            operations += spreadBody();
        return operations;
    }
    case 2:
        churn(&state, CHURN_SLOTS, 10000000, smallSize, 0, latency, 0);
        return 10000000;
    case 3:
        churn(&state, MEDIUM_SLOTS, 2000000, mediumSize, 0, latency, 1);
        return 2000000;
    case 4:
        churn(&state, LARGE_SLOTS, 200000, largeSize, 1, latency, 1);
        return 200000;
    case 5:
    {
        uint64_t operations = 0;
        if (latency)
            latency->unit = 1;
        for (int i = 0; i < 2000; i++)
        {
            uint64_t size  = 16;
            char*    block = (char*)ALLOC(size);
            while (size < 4 * 1024 * 1024)
            {
                uint64_t start = latency ? ticks() : 0;
                block = (char*)REALLOC(block, size * 2);
                size *= 2;
                block[size - 1] = 1;
                operations++;
                if (latency)
                    record(latency, ticks() - start);
            }
            FREE(block);
        }
        return operations;
    }
    case 8:
    {
        const uint64_t count     = 4000000;
        char**         addresses = (char**)ALLOC(count * sizeof(char*));
        for (uint64_t i = 0; i < count; i++)
        {
            addresses[i]    = (char*)ALLOC(32);
            addresses[i][0] = 1;
        }
        for (uint64_t i = 0; i < count; i++)
            FREE(addresses[i]);
        FREE(addresses);
        return count * 2;
    }
    case 6:
        return spreadBody();
    }
    return 0;
}

typedef struct
{
    void* volatile    slots[XFER_RING];
    volatile uint64_t head;
    volatile uint64_t tail;
} Ring;

/* Workers of a gated workload arrive here before the phase clock starts, and leave together. */
typedef struct
{
    volatile LONG64 arrived;
    volatile LONG64 open;
} Gate;

typedef struct
{
    int      workload;
    uint64_t seed;
    uint64_t operations;
    uint64_t bodyTicks;
    Ring*    ring;
    Gate*    gate;
    Latency* latency;
    int      producer;
} Job;

static Ring rings[16];

static void produce(Ring* ring, uint64_t seed)
{
    uint64_t state = seed;
    for (int i = 0; i < XFER_COUNT; i++)
    {
        char* block = (char*)ALLOC(smallSize(&state));
        block[0]    = 1;
        while (ring->head - ring->tail >= XFER_RING) {}
        ring->slots[ring->head % XFER_RING] = block;
        InterlockedExchange64((volatile LONG64*)&ring->head, ring->head + 1);
    }
}

/* With a recorder, every batch of the consumer's remote frees is timed, waiting for the producer excluded. */
static void consume(Ring* ring, Latency* latency)
{
    if (latency)
        latency->unit = LATENCY_BATCH;
    uint64_t spent = 0;
    for (int i = 0; i < XFER_COUNT; i++)
    {
        while (ring->head == ring->tail) {}
        uint64_t start = latency ? ticks() : 0;
        FREE(ring->slots[ring->tail % XFER_RING]);
        InterlockedExchange64((volatile LONG64*)&ring->tail, ring->tail + 1);
        if (latency)
        {
            spent += ticks() - start;
            if ((uint64_t)(i + 1) % LATENCY_BATCH == 0)
            {
                record(latency, spent);
                spent = 0;
            }
        }
    }
}

/* One worker: waits at the gate when the workload has one, then times its own work. */
static DWORD WINAPI threadEntry(void* param)
{
    Job* job = (Job*)param;
    if (job->gate)
    {
        InterlockedIncrement64(&job->gate->arrived);
        while (!job->gate->open) {}
    }

    uint64_t start = ticks();
    if (job->workload != 7)
        job->operations = run(job->workload, job->seed, job->latency);
    else if (job->producer)
        produce(job->ring, job->seed);
    else
    {
        consume(job->ring, job->latency);
        job->operations = XFER_COUNT;
    }
    job->bodyTicks = ticks() - start;
    return 0;
}

int main(int argc, char** argv)
{
    static const char* names[] = {"pair", "trees", "churn", "medium", "large", "realloc", "spread", "xfer", "grow", "aligned", "huge", "spreadrep", "retain"};
    int                workload = -1;
    for (int i = 0; i < 13; i++)
    {
        if (argc > 1 && !strcmp(argv[1], names[i]))
            workload = i;
    }

    int threads = argc > 2 ? atoi(argv[2]) : 1;
    int latency = argc > 3 && !strcmp(argv[3], "latency");
    if (workload < 0 || threads < 1 || threads > 16)
    {
        printf("usage: allocbench <pair|trees|churn|medium|large|realloc|spread|grow|xfer|aligned|huge|spreadrep|retain> [threads 1-16] [latency]\n");
        return 0;
    }

    QueryPerformanceFrequency(&clockFrequency);
    if (workload == 12)
    {
        uint64_t state = 1000, idle, purged, trimmed;
        retain(&state, &idle, &purged, &trimmed);
        printf("allocbench workload=retain threads=1 operations=1 ns/op=0 retained_idle=%llu retained_purged=%llu retained_trimmed=%llu\n",
               (unsigned long long)idle, (unsigned long long)purged, (unsigned long long)trimmed);
        return 0;
    }

    Job     jobs[32];
    HANDLE  handles[32];
    Gate    gate     = {0, 0};
    Latency recorder = {NULL, 0, 0};
    int     count    = workload == 7 ? threads * 2 : threads;
    int     gated    = workload == 11;
    if (latency)
        recorder.samples = (uint32_t*)ALLOC(LATENCY_MAX_SAMPLES * sizeof(uint32_t));

    LARGE_INTEGER start, stop;
    QueryPerformanceCounter(&start);
    for (int i = 0; i < count; i++)
    {
        jobs[i].workload   = workload;
        jobs[i].seed       = 1000 + (uint64_t)i * 7919;
        jobs[i].operations = 0;
        jobs[i].bodyTicks  = 0;
        jobs[i].ring       = workload == 7 ? &rings[i / 2] : NULL;
        jobs[i].gate       = gated ? &gate : NULL;
        jobs[i].latency    = latency && i == (workload == 7 ? 1 : 0) ? &recorder : NULL;
        jobs[i].producer   = i % 2 == 0;
        handles[i]         = CreateThread(NULL, 0, threadEntry, &jobs[i], 0, NULL);
    }

    /* The phase clock of a gated workload starts once every worker has arrived. */
    uint64_t phaseStart = 0;
    if (gated)
    {
        while (gate.arrived < count) {}
        phaseStart = ticks();
        InterlockedExchange64(&gate.open, 1);
    }

    WaitForMultipleObjects(count, handles, TRUE, INFINITE);
    uint64_t phaseTicks = gated ? ticks() - phaseStart : 0;
    for (int i = 0; i < count; i++)
        CloseHandle(handles[i]);
    QueryPerformanceCounter(&stop);

    uint64_t operations = 0;
    double   slowest    = 0;
    for (int i = 0; i < count; i++)
    {
        operations += jobs[i].operations;
        if (!jobs[i].operations)
            continue; /* A producer counts no operation of its own: the consumer counts the pair's. */
        double perOp = (double)jobs[i].bodyTicks * 1e9 / (double)clockFrequency.QuadPart / (double)jobs[i].operations;
        if (perOp > slowest)
            slowest = perOp;
    }
    double ns = (double)(stop.QuadPart - start.QuadPart) * 1e9 / (double)clockFrequency.QuadPart / (double)operations;
    printf("allocbench workload=%s threads=%d operations=%llu ns/op=%f worker_ns/op=%f", argv[1], threads, (unsigned long long)operations, ns, slowest);
    if (gated)
        printf(" phase_ns/op=%f", (double)phaseTicks * 1e9 / (double)clockFrequency.QuadPart / (double)operations);
    if (latency)
        printf(" p50_ns=%f p99_ns=%f per_ops=%llu", percentile(&recorder, 500), percentile(&recorder, 990), (unsigned long long)recorder.unit);
    printf("\n");
    return 0;
}
