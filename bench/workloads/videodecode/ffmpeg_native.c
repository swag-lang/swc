#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/cpu.h>

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

static void receive(AVCodecContext *codec, AVFrame *frame, unsigned *count,
                    unsigned warmup, double *start, double *cpu)
{
    for (;;)
    {
        int result = avcodec_receive_frame(codec, frame);
        if (result == AVERROR(EAGAIN) || result == AVERROR_EOF)
            return;
        check(result);
        if (++*count == warmup)
        {
            *start = seconds(CLOCK_MONOTONIC);
            *cpu = seconds(CLOCK_THREAD_CPUTIME_ID);
        }
        av_frame_unref(frame);
    }
}

int main(int argc, char **argv)
{
    if (argc != 4 && argc != 5)
        return 2;
    const unsigned repeats = strtoul(argv[2], NULL, 10);
    const unsigned warmup = argc == 5 ? strtoul(argv[4], NULL, 10) : 30;
    if (!warmup)
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
        if (!codec || !packet || !frame)
            abort();
        check(avcodec_parameters_to_context(codec, params));
        codec->thread_count = 1;
        check(avcodec_open2(codec, decoder, NULL));

        double start = 0, cpu = 0;
        unsigned count = 0;
        int result;
        while ((result = av_read_frame(format, packet)) >= 0)
        {
            if ((unsigned)packet->stream_index == video)
            {
                check(avcodec_send_packet(codec, packet));
                receive(codec, frame, &count, warmup, &start, &cpu);
            }
            av_packet_unref(packet);
        }
        if (result != AVERROR_EOF)
            check(result);
        check(avcodec_send_packet(codec, NULL));
        receive(codec, frame, &count, warmup, &start, &cpu);
        if (count <= warmup)
            abort();
        if (rep)
            printf("video frames=%u wall=%.9f cpu=%.9f\n", count - warmup,
                   seconds(CLOCK_MONOTONIC) - start, seconds(CLOCK_THREAD_CPUTIME_ID) - cpu);
        avcodec_free_context(&codec);
        avformat_close_input(&format);
        av_packet_free(&packet);
        av_frame_free(&frame);
    }
}
