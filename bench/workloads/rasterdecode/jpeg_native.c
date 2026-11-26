#define _POSIX_C_SOURCE 200809L

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <jpeglib.h>

#define STRINGIFY_VALUE(value) #value
#define STRINGIFY(value) STRINGIFY_VALUE(value)

static uint64_t time_ns(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
        exit(EXIT_FAILURE);
    return (uint64_t)now.tv_sec * 1000000000 + now.tv_nsec;
}

static int decode(const char *path, int measure)
{
    struct jpeg_decompress_struct decoder;
    struct jpeg_error_mgr error;
    const uint64_t started = time_ns();
    FILE *input = fopen(path, "rb");
    if (!input)
    {
        perror(path);
        exit(EXIT_FAILURE);
    }
    decoder.err = jpeg_std_error(&error);
    jpeg_create_decompress(&decoder);
    jpeg_stdio_src(&decoder, input);
    jpeg_read_header(&decoder, TRUE);
    if (decoder.jpeg_color_space == JCS_CMYK || decoder.jpeg_color_space == JCS_YCCK)
    {
        jpeg_destroy_decompress(&decoder);
        fclose(input);
        return 0;
    }
    decoder.out_color_space = JCS_EXT_BGR;
    jpeg_start_decompress(&decoder);
    const size_t stride = (size_t)decoder.output_width * decoder.output_components;
    if (decoder.output_height > SIZE_MAX / stride)
        exit(EXIT_FAILURE);
    unsigned char *pixels = malloc(stride * decoder.output_height);
    if (!pixels)
        exit(EXIT_FAILURE);
    while (decoder.output_scanline < decoder.output_height)
    {
        JSAMPROW rows[16];
        JDIMENSION count = decoder.output_height - decoder.output_scanline;
        if (count > 16)
            count = 16;
        for (JDIMENSION index = 0; index < count; ++index)
            rows[index] = pixels + (decoder.output_scanline + index) * stride;
        jpeg_read_scanlines(&decoder, rows, count);
    }
    jpeg_finish_decompress(&decoder);
    const uint64_t elapsed = time_ns() - started;
    if (measure)
        printf("%llu %u %u %d\n", (unsigned long long)(elapsed / 1000),
               decoder.output_width, decoder.output_height, decoder.output_components);
    free(pixels);
    jpeg_destroy_decompress(&decoder);
    fclose(input);
    return 1;
}

int main(int argc, char **argv)
{
    if (argc != 2)
        return EXIT_FAILURE;
    if (strcmp(argv[1], "--version") == 0)
        puts(STRINGIFY(LIBJPEG_TURBO_VERSION));
    else if (decode(argv[1], 0))
        decode(argv[1], 1);
    else
        puts("unsupported");
    return EXIT_SUCCESS;
}
