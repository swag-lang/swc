#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core

// A framebuffer transfer exercises an extension call with ten native C ABI arguments.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var window  = expect Env.createWindow({identifier: "ogl-framebuffer-test", title: "OpenGL framebuffer test", width: 32, height: 32})
    var context = expect Platform.Win32.createContext(&window)
    glInitExtensions()
    var textures: [2] GLuint
    var buffers:  [2] GLuint
    glGenTextures(2, &textures[0])
    glGenFramebuffers(2, &buffers[0])
    defer glDeleteTextures(2, &textures[0])
    defer glDeleteFramebuffers(2, &buffers[0])
    for index in 2
    {
        glBindTexture(GL_TEXTURE_2D, textures[index])
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 32, 32, 0, GL_RGBA, GL_UNSIGNED_BYTE, null)
        glBindFramebuffer(GL_FRAMEBUFFER, buffers[index])
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, textures[index], 0)
        Swag.assert(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE)
        glClearColor(index == 0 ? 1.0 : 0.0, 0, 0, 1)
        glClear(GL_COLOR_BUFFER_BIT)
    }

    Swag.assert(glGetError() == GL_NO_ERROR)
    glBindFramebuffer(GL_READ_FRAMEBUFFER, buffers[0])
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, buffers[1])
    glBlitFramebuffer(0, 32, 32, 0, 0, 0, 32, 32, GL_COLOR_BUFFER_BIT, GL_NEAREST)
    Swag.assert(glGetError() == GL_NO_ERROR)
    glBindFramebuffer(GL_READ_FRAMEBUFFER, buffers[1])
    var pixel: u32
    glReadPixels(16, 16, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, cast([*] u8) &pixel)
    Swag.assert(pixel == 0xFF0000FF)
}
