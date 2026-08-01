#global public

using Swag

#[Extension, Swag.PlaceHolder]

{
    func glBindBuffersBase(target: GLenum, first: GLuint, count: GLsizei, buffers: #null const *GLuint)

    func glBindBuffersRange(target: GLenum, first: GLuint, count: GLsizei, buffers: #null const *GLuint, offsets: #null const *GLintptr, sizes: #null const *GLsizeiptr)

    func glBindImageTextures(first: GLuint, count: GLsizei, textures: #null const *GLuint)

    func glBindSamplers(first: GLuint, count: GLsizei, samplers: #null const *GLuint)

    func glBindTextures(first: GLuint, count: GLsizei, textures: #null const *GLuint)

    func glBindVertexBuffers(first: GLuint, count: GLsizei, buffers: #null const *GLuint, offsets: #null const *GLintptr, strides: #null const *GLsizei)

    func glBufferStorage(target: GLenum, size: GLsizeiptr, data: #null const *void, flags: GLbitfield)

    func glClearTexImage(texture: GLuint, level: GLint, format: GLenum, type: GLenum, data: #null const *void)

    func glClearTexSubImage(texture: GLuint, level: GLint, xoffset: GLint, yoffset: GLint, zoffset: GLint, width: GLsizei, height: GLsizei, depth: GLsizei, format: GLenum, type: GLenum, data: #null const *void)
}

const GL_PRIMITIVE_RESTART_FOR_PATCHES_SUPPORTED = 0x8221

const GL_MAX_VERTEX_ATTRIB_STRIDE = 0x82E5

const GL_TEXTURE_BUFFER_BINDING = 0x8C2A

const GL_MAP_PERSISTENT_BIT = 0x0040

const GL_MAP_COHERENT_BIT = 0x0080

const GL_DYNAMIC_STORAGE_BIT = 0x0100

const GL_CLIENT_STORAGE_BIT = 0x0200

const GL_CLIENT_MAPPED_BUFFER_BARRIER_BIT = 0x00004000

const GL_BUFFER_IMMUTABLE_STORAGE = 0x821F

const GL_BUFFER_STORAGE_FLAGS = 0x8220

const GL_CLEAR_TEXTURE = 0x9365

const GL_LOCATION_COMPONENT = 0x934A

const GL_TRANSFORM_FEEDBACK_BUFFER_INDEX = 0x934B

const GL_TRANSFORM_FEEDBACK_BUFFER_STRIDE = 0x934C

const GL_QUERY_BUFFER = 0x9192

const GL_QUERY_BUFFER_BARRIER_BIT = 0x00008000

const GL_QUERY_BUFFER_BINDING = 0x9193

const GL_QUERY_RESULT_NO_WAIT = 0x9194

const GL_MIRROR_CLAMP_TO_EDGE = 0x8743
