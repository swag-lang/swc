#ifndef SWAG_AUDIOENCODE_NATIVE_INPUT_H
#define SWAG_AUDIOENCODE_NATIVE_INPUT_H

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/types.h>

static uint64_t micros(void)
{
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return (uint64_t)time.tv_sec * 1000000 + time.tv_nsec / 1000;
}

static void require(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "%s\n", message);
        exit(1);
    }
}

static int number(const char *text, int minimum, int maximum)
{
    char *end;
    errno = 0;
    long value = strtol(text, &end, 10);
    require(!errno && *text && !*end && value >= minimum && value <= maximum, "Invalid numeric option");
    return (int)value;
}

static int16_t *read_pcm(const char *path, int channels, uint64_t *frames)
{
    FILE *file = fopen(path, "rb");
    require(file != NULL, "Cannot open PCM input");
    require(!fseeko(file, 0, SEEK_END), "Cannot seek PCM input");
    off_t size = ftello(file);
    require(size > 0 && (uintmax_t)size <= SIZE_MAX &&
            !(size % ((off_t)sizeof(int16_t) * channels)), "PCM input must contain whole frames");
    require(!fseeko(file, 0, SEEK_SET), "Cannot rewind PCM input");
    int16_t *samples = malloc((size_t)size);
    require(samples != NULL, "Cannot allocate PCM input");
    require(fread(samples, 1, (size_t)size, file) == (size_t)size, "Incomplete PCM input");
    require(!fclose(file), "Cannot close PCM input");
    *frames = (uint64_t)size / (sizeof(*samples) * channels);
    return samples;
}

#endif
