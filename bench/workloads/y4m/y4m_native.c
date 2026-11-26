#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <libavutil/imgutils.h>
#include <libavutil/mem.h>
#include <libswscale/swscale.h>

static void check(int result)
{
    if (result >= 0)
        return;
    char error[AV_ERROR_MAX_STRING_SIZE];
    fprintf(stderr, "%s\n", av_make_error_string(error, sizeof(error), result));
    exit(1);
}

static int number(const char *text, int minimum, int maximum)
{
    char *end;
    errno = 0;
    const long result = strtol(text, &end, 10);
    if (errno || end == text || *end || result < minimum || result > maximum)
    {
        fprintf(stderr, "invalid numeric argument: %s\n", text);
        exit(2);
    }
    return (int)result;
}

static uint64_t ticks(clockid_t clock)
{
    struct timespec value;
    if (clock_gettime(clock, &value))
        abort();
    return (uint64_t)value.tv_sec * 1000000000 + value.tv_nsec;
}

int main(int argc, char **argv)
{
    if (argc != 7)
    {
        fprintf(stderr, "usage: y4m_native input.rgb output.y4m width height count layout\n");
        return 2;
    }
    const int width = number(argv[3], 1, 65500);
    const int height = number(argv[4], 1, 65500);
    const int count = number(argv[5], 1, 10000);
    const int layout = number(argv[6], 0, 3);
    const enum AVPixelFormat layouts[] = {AV_PIX_FMT_YUV411P, AV_PIX_FMT_YUV420P,
                                          AV_PIX_FMT_YUV422P, AV_PIX_FMT_YUV444P};
    const char *tags[] = {"411", "420jpeg", "422", "444"};
    if ((layout == 0 && width % 4) || (layout == 1 && (width % 2 || height % 2)) ||
        (layout == 2 && width % 2))
        return 2;
    const enum AVPixelFormat format = layouts[layout];
    const int source_stride = width * 3;
    const size_t source_size = (size_t)source_stride * height;
    const int frame_size = av_image_get_buffer_size(format, width, height, 1);
    check(frame_size);
    uint8_t *rgb = av_mallocz(source_size * count + 64);
    uint8_t *frames = av_malloc((size_t)frame_size * count);
    if (!rgb || !frames)
        check(AVERROR(ENOMEM));
    FILE *input = fopen(argv[1], "rb");
    if (!input)
        check(AVERROR(errno));
    if (fread(rgb, source_size, count, input) != (size_t)count || fgetc(input) != EOF || ferror(input))
        check(AVERROR_INVALIDDATA);
    fclose(input);

    struct SwsContext *convert = sws_getContext(width, height, AV_PIX_FMT_RGB24, width, height, format,
                                               SWS_AREA, NULL, NULL, NULL);
    if (!convert)
        check(AVERROR(ENOMEM));
    const int *matrix = sws_getCoefficients(SWS_CS_ITU601);
    check(sws_setColorspaceDetails(convert, matrix, 1, matrix, 0, 0, 1 << 16, 1 << 16));
    uint8_t *planes[4] = {0};
    int pitches[4] = {0};
    check(av_image_alloc(planes, pitches, width, height, format, 32));
    const int source_pitches[4] = {-source_stride, 0, 0, 0};
    uint64_t wall = ticks(CLOCK_MONOTONIC);
    uint64_t cpu = ticks(CLOCK_PROCESS_CPUTIME_ID);
    for (int index = 0; index < count; ++index)
    {
        const uint8_t *source[4] = {rgb + index * source_size + (size_t)(height - 1) * source_stride};
        if (sws_scale(convert, source, source_pitches, 0, height, planes, pitches) != height)
            check(AVERROR_INVALIDDATA);
        check(av_image_copy_to_buffer(frames + (size_t)index * frame_size, frame_size,
                                      (const uint8_t *const *)planes, pitches, format, width, height, 1));
    }
    cpu = ticks(CLOCK_PROCESS_CPUTIME_ID) - cpu;
    wall = ticks(CLOCK_MONOTONIC) - wall;

    FILE *output = fopen(argv[2], "wb");
    if (!output)
        check(AVERROR(errno));
    if (fprintf(output, "YUV4MPEG2 W%d H%d F30:1 Ip A0:0 C%s XCOLORRANGE=LIMITED\n",
                width, height, tags[layout]) < 0)
        check(AVERROR(EIO));
    for (int index = 0; index < count; ++index)
    {
        if (fputs("FRAME\n", output) == EOF ||
            fwrite(frames + (size_t)index * frame_size, 1, frame_size, output) != (size_t)frame_size)
            check(AVERROR(EIO));
    }
    if (fclose(output))
        check(AVERROR(errno));

    sws_freeContext(convert);
    av_free(planes[0]);
    av_free(frames);
    av_free(rgb);
    printf("Y4M frames=%d us=%" PRIu64 " cpu_us=%" PRIu64 " bytes=%zu\n",
           count, wall / 1000, cpu / 1000, (size_t)frame_size * count);
}
