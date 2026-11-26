#define _POSIX_C_SOURCE 200809L

#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include <ft2build.h>
#include FT_FREETYPE_H

enum source_kind
{
    FILE_PATH,
    OWNED_SNAPSHOT,
    MEMORY_BUFFER,
    COUNTED_STREAM
};

struct counted_stream
{
    const unsigned char *bytes;
    unsigned long length;
    unsigned long bytes_read;
};

static void require(int condition, const char *operation)
{
    if (!condition)
    {
        fprintf(stderr, "%s failed\n", operation);
        exit(EXIT_FAILURE);
    }
}

static unsigned long read_stream(FT_Stream stream, unsigned long offset,
                                 unsigned char *buffer, unsigned long count)
{
    struct counted_stream *data = stream->descriptor.pointer;
    if (offset > data->length)
        return count ? 0 : 1;
    if (count > data->length - offset)
        return 0;
    if (count)
    {
        memcpy(buffer, data->bytes + offset, count);
        data->bytes_read += count;
    }
    return count;
}

static uint64_t time_ns(void)
{
    struct timespec now;
    require(clock_gettime(CLOCK_MONOTONIC, &now) == 0, "clock_gettime");
    return (uint64_t)now.tv_sec * 1000000000 + now.tv_nsec;
}

int main(int argc, char **argv)
{
    FT_Library library;
    require(FT_Init_FreeType(&library) == 0, "FT_Init_FreeType");
    if (argc == 2 && strcmp(argv[1], "--version") == 0)
    {
        FT_Int major, minor, patch;
        FT_Library_Version(library, &major, &minor, &patch);
        printf("%d.%d.%d\n", major, minor, patch);
        FT_Done_FreeType(library);
        return EXIT_SUCCESS;
    }

    require(argc == 7 || argc == 8, "expected mode, font path, face index, glyph, size, sample count and optional warmups");
    enum source_kind source = FILE_PATH;
    if (strcmp(argv[1], "snapshot") == 0)
        source = OWNED_SNAPSHOT;
    else if (strcmp(argv[1], "memory") == 0)
        source = MEMORY_BUFFER;
    else if (strcmp(argv[1], "count") == 0)
        source = COUNTED_STREAM;
    else
        require(strcmp(argv[1], "file") == 0, "expected file, snapshot, memory or count mode");

    const char *path = argv[2];
    const long index = strtol(argv[3], NULL, 0);
    const unsigned long character = strtoul(argv[4], NULL, 0);
    const long pixels = strtol(argv[5], NULL, 0);
    const unsigned long samples = strtoul(argv[6], NULL, 0);
    require(index >= 0 && pixels > 0 && pixels <= 65535, "invalid face index or pixel size");
    require(samples > 0 && samples <= 100000, "invalid sample count");

    int fd = -1;
    unsigned long length = 0;
    unsigned char *buffer = NULL;
    if (source != FILE_PATH)
    {
        struct stat file;
        fd = open(path, O_RDONLY | O_CLOEXEC);
        require(fd >= 0 && fstat(fd, &file) == 0 && file.st_size > 0, "open font");
        length = (unsigned long)file.st_size;
        buffer = malloc(length);
        require(buffer != NULL, "allocate font buffer");
        require(pread(fd, buffer, length, 0) == file.st_size, "warm font buffer");
    }

    uint64_t input_ns = 0;
    uint64_t face_ns = 0;
    uint64_t glyph_ns = 0;
    unsigned long open_bytes = 0;
    unsigned long glyph_bytes = 0;
    unsigned long glyph = 0;
    char *warmup_end = NULL;
    const unsigned long warmups = argc == 8 ? strtoul(argv[7], &warmup_end, 0) : 5;
    require(warmups <= 100000 && (!warmup_end || (warmup_end != argv[7] && !*warmup_end)), "invalid warmup count");
    FT_Size_RequestRec size = {FT_SIZE_REQUEST_TYPE_NOMINAL, 0, pixels * 64, 0, 0};
    for (unsigned long i = 0; i < samples + warmups; ++i)
    {
        FT_Face face;
        struct counted_stream counted = {buffer, length, 0};
        FT_StreamRec stream = {.size = length, .descriptor.pointer = &counted, .read = read_stream};
        FT_Open_Args args = {.flags = FT_OPEN_STREAM, .stream = &stream};
        const uint64_t start = time_ns();
        uint64_t input_done = start;
        if (source == FILE_PATH)
        {
            require(FT_New_Face(library, path, index, &face) == 0, "FT_New_Face");
        }
        else if (source == COUNTED_STREAM)
        {
            require(FT_Open_Face(library, &args, index, &face) == 0, "FT_Open_Face");
        }
        else
        {
            if (source == OWNED_SNAPSHOT)
            {
                require(pread(fd, buffer, length, 0) == (ssize_t)length, "read font snapshot");
                input_done = time_ns();
            }

            require(FT_New_Memory_Face(library, buffer, length, index, &face) == 0, "FT_New_Memory_Face");
        }

        require(FT_Request_Size(face, &size) == 0, "FT_Request_Size");
        const uint64_t face_done = time_ns();
        const unsigned long face_bytes = counted.bytes_read;
        glyph = FT_Get_Char_Index(face, character);
        require(glyph && FT_Load_Glyph(face, glyph, FT_LOAD_RENDER) == 0, "FT_Load_Glyph");
        const uint64_t glyph_done = time_ns();
        require(face->glyph->bitmap.width && face->glyph->bitmap.rows, "empty glyph");
        require(FT_Done_Face(face) == 0, "FT_Done_Face");
        if (i < warmups)
            continue;

        input_ns += input_done - start;
        face_ns += face_done - input_done;
        glyph_ns += glyph_done - face_done;
        open_bytes += face_bytes;
        glyph_bytes += counted.bytes_read - face_bytes;
    }

    printf("%llu %llu %llu %lu %lu %lu\n",
           (unsigned long long)(input_ns / samples), (unsigned long long)(face_ns / samples),
           (unsigned long long)(glyph_ns / samples), open_bytes / samples, glyph_bytes / samples, glyph);
    if (fd >= 0)
        close(fd);
    free(buffer);
    FT_Done_FreeType(library);
    return EXIT_SUCCESS;
}
