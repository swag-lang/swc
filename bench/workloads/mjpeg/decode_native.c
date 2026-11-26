#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <libavformat/avformat.h>
#include <jpeglib.h>

#define STRINGIFY_IMPL(value) #value
#define STRINGIFY(value) STRINGIFY_IMPL(value)

static double seconds(clockid_t clock)
{
    struct timespec ts;
    if (clock_gettime(clock, &ts))
        abort();
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

static void check(int result)
{
    if (result >= 0)
        return;
    char error[AV_ERROR_MAX_STRING_SIZE];
    fprintf(stderr, "%s\n", av_make_error_string(error, sizeof(error), result));
    exit(1);
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "--version"))
    {
        puts("libjpeg-turbo " STRINGIFY(LIBJPEG_TURBO_VERSION));
        return 0;
    }
    if (argc != 4)
        return 2;
    const unsigned repeats = strtoul(argv[2], NULL, 10);
    const unsigned warmup = strtoul(argv[3], NULL, 10);
    if (!repeats || !warmup)
        return 2;

    for (unsigned rep = 0; rep <= repeats; ++rep)
    {
        AVFormatContext *format = NULL;
        check(avformat_open_input(&format, argv[1], NULL, NULL));
        unsigned video = 0;
        while (video < format->nb_streams && format->streams[video]->codecpar->codec_type != AVMEDIA_TYPE_VIDEO)
            ++video;
        if (video == format->nb_streams || format->streams[video]->codecpar->codec_id != AV_CODEC_ID_MJPEG)
            check(AVERROR_STREAM_NOT_FOUND);

        AVPacket *packet = av_packet_alloc();
        if (!packet)
            abort();
        struct jpeg_error_mgr errors;
        struct jpeg_decompress_struct decoder;
        decoder.err = jpeg_std_error(&errors);
        jpeg_create_decompress(&decoder);

        unsigned count = 0, width = 0, height = 0;
        double start = 0, cpu = 0;
        unsigned char *pixels = NULL;
        int result;
        while ((result = av_read_frame(format, packet)) >= 0)
        {
            if ((unsigned)packet->stream_index == video)
            {
                if (packet->size <= 0)
                    abort();
                jpeg_mem_src(&decoder, packet->data, packet->size);
                if (jpeg_read_header(&decoder, TRUE) != JPEG_HEADER_OK)
                    abort();
                decoder.out_color_space = JCS_RGB;
                decoder.do_fancy_upsampling = FALSE;
                jpeg_start_decompress(&decoder);
                if (!pixels)
                {
                    width = decoder.output_width;
                    height = decoder.output_height;
                    pixels = malloc((size_t)width * height * 3);
                    if (!pixels)
                        abort();
                }
                if (decoder.output_width != width || decoder.output_height != height ||
                    decoder.output_components != 3)
                    abort();
                while (decoder.output_scanline < height)
                {
                    JSAMPROW row = pixels + (size_t)decoder.output_scanline * width * 3;
                    if (jpeg_read_scanlines(&decoder, &row, 1) != 1)
                        abort();
                }
                jpeg_finish_decompress(&decoder);
                if (++count == warmup)
                {
                    start = seconds(CLOCK_MONOTONIC);
                    cpu = seconds(CLOCK_PROCESS_CPUTIME_ID);
                }
            }
            av_packet_unref(packet);
        }
        if (result != AVERROR_EOF)
            check(result);
        if (count <= warmup)
            abort();
        if (rep)
            printf("video frames=%u wall=%.9f cpu=%.9f\n", count - warmup,
                   seconds(CLOCK_MONOTONIC) - start, seconds(CLOCK_PROCESS_CPUTIME_ID) - cpu);
        free(pixels);
        jpeg_destroy_decompress(&decoder);
        av_packet_free(&packet);
        avformat_close_input(&format);
    }
}
