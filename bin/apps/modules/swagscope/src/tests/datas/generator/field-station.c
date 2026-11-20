#include <stdint.h>
#include <stdio.h>

typedef struct {
    const char *site;
    uint32_t sample_count;
    float water_level_cm;
} StationSummary;

static const StationSummary stations[] = {
    {"north-marsh", 18, 38.4f},
    {"old-quarry", 12, 11.7f},
    {"river-gate", 21, 43.2f},
};

static float mean_water_level(void)
{
    float total = 0.0f;
    for (uint32_t i = 0; i < sizeof(stations) / sizeof(stations[0]); ++i)
        total += stations[i].water_level_cm;
    return total / (float)(sizeof(stations) / sizeof(stations[0]));
}

int main(int argc, char **argv)
{
    (void)argv;
    if (argc > 1)
        puts("Field station summary is fictional test data.");
    printf("%u observations across %zu sites; mean water level %.1f cm\n",
           stations[0].sample_count + stations[1].sample_count + stations[2].sample_count,
           sizeof(stations) / sizeof(stations[0]), mean_water_level());
    return 0;
}
