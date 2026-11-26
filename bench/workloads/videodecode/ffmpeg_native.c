#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/cpu.h>
#include <libavutil/pixdesc.h>
#include <libswscale/swscale.h>

struct RgbOutput
{
    struct SwsContext *scale;
    AVFrame *frame;
    int source_format;
};

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

static void convert_rgb(struct RgbOutput *rgb, const AVFrame *frame)
{
    if (!rgb->scale)
    {
        rgb->scale = sws_getContext(frame->width, frame->height, frame->format,
                                    frame->width, frame->height, AV_PIX_FMT_RGB24,
                                    SWS_POINT, NULL, NULL, NULL);
        if (!rgb->scale)
            abort();
        const AVPixFmtDescriptor *layout = av_pix_fmt_desc_get(frame->format);
        if (!layout)
            abort();
        if (!(layout->flags & AV_PIX_FMT_FLAG_RGB))
        {
            const int *coefficients = sws_getCoefficients(SWS_CS_ITU601);
            check(sws_setColorspaceDetails(rgb->scale, coefficients, frame->color_range == AVCOL_RANGE_JPEG,
                                          coefficients, 1, 0, 1 << 16, 1 << 16));
        }
        rgb->frame->width = frame->width;
        rgb->frame->height = frame->height;
        rgb->frame->format = AV_PIX_FMT_RGB24;
        rgb->source_format = frame->format;
        check(av_frame_get_buffer(rgb->frame, 32));
    }
    if (rgb->frame->width != frame->width || rgb->frame->height != frame->height ||
        rgb->source_format != frame->format)
        abort();
    int rows = sws_scale(rgb->scale, (const uint8_t * const *)frame->data, frame->linesize,
                         0, frame->height, rgb->frame->data, rgb->frame->linesize);
    if (rows != frame->height)
        abort();
}

static void receive(AVCodecContext *codec, AVFrame *frame, unsigned *count,
                    unsigned warmup, double *start, double *cpu, struct RgbOutput *rgb)
{
    for (;;)
    {
        int result = avcodec_receive_frame(codec, frame);
        if (result == AVERROR(EAGAIN) || result == AVERROR_EOF)
            return;
        check(result);
        if (rgb)
            convert_rgb(rgb, frame);
        if (++*count == warmup)
        {
            *start = seconds(CLOCK_MONOTONIC);
            *cpu = seconds(CLOCK_PROCESS_CPUTIME_ID);
        }
        av_frame_unref(frame);
    }
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "--version"))
    {
        puts(av_version_info());
        return 0;
    }
    if (argc < 4 || argc > 7 || (argc == 7 && strcmp(argv[6], "rgb")))
        return 2;
    const unsigned repeats = strtoul(argv[2], NULL, 10);
    const unsigned warmup = argc >= 5 ? strtoul(argv[4], NULL, 10) : 30;
    const unsigned long lanes = argc >= 6 ? strtoul(argv[5], NULL, 10) : 1;
    if (!warmup || !lanes || lanes > INT_MAX)
        return 2;
    if (atoi(argv[3]))
        av_force_cpu_flags(0);
    for (unsigned rep = 0; rep <= repeats; ++rep)
    {
        AVFormatContext *format = NULL;
        check(avformat_open_input(&format, argv[1], NULL, NULL));
        unsigned video = 0;
        while (video < format->nb_streams && format->streams[video]->codecpar->codec_type != AVMEDIA_TYPE_VIDEO)
            ++video;
        if (video == format->nb_streams)
            check(AVERROR_STREAM_NOT_FOUND);
        const AVCodecParameters *params = format->streams[video]->codecpar;
        const AVCodec *decoder = avcodec_find_decoder(params->codec_id);
        if (!decoder)
            check(AVERROR_DECODER_NOT_FOUND);
        AVCodecContext *codec = avcodec_alloc_context3(decoder);
        AVPacket *packet = av_packet_alloc();
        AVFrame *frame = av_frame_alloc();
        struct RgbOutput rgb = {.frame = argc == 7 ? av_frame_alloc() : NULL};
        if (!codec || !packet || !frame || (argc == 7 && !rgb.frame))
            abort();
        check(avcodec_parameters_to_context(codec, params));
        codec->thread_count = (int)lanes;
        check(avcodec_open2(codec, decoder, NULL));

        double start = 0, cpu = 0;
        unsigned count = 0;
        int result;
        while ((result = av_read_frame(format, packet)) >= 0)
        {
            if ((unsigned)packet->stream_index == video)
            {
                check(avcodec_send_packet(codec, packet));
                receive(codec, frame, &count, warmup, &start, &cpu, rgb.frame ? &rgb : NULL);
            }
            av_packet_unref(packet);
        }
        if (result != AVERROR_EOF)
            check(result);
        check(avcodec_send_packet(codec, NULL));
        receive(codec, frame, &count, warmup, &start, &cpu, rgb.frame ? &rgb : NULL);
        if (count <= warmup)
            abort();
        if (rep)
            printf("video frames=%u wall=%.9f cpu=%.9f\n", count - warmup,
                   seconds(CLOCK_MONOTONIC) - start, seconds(CLOCK_PROCESS_CPUTIME_ID) - cpu);
        avcodec_free_context(&codec);
        avformat_close_input(&format);
        av_packet_free(&packet);
        av_frame_free(&frame);
        sws_freeContext(rgb.scale);
        av_frame_free(&rgb.frame);
    }
}
