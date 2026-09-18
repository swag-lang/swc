#global public

using Swag

/* ---------------------- GL_MESA_framebuffer_flip_x ----------------------- */

const GL_MESA_framebuffer_flip_x = 1
const GL_FRAMEBUFFER_FLIP_X_MESA = 0x8BBC

/* ---------------------- GL_MESA_framebuffer_flip_y ----------------------- */

const GL_MESA_framebuffer_flip_y = 1
const GL_FRAMEBUFFER_FLIP_Y_MESA = 0x8BBB

#[Extension, Swag.PlaceHolder]
{
    func glFramebufferParameteriMESA(target: GLenum, pname: GLenum, param: GLint)
    func glGetFramebufferParameterivMESA(target: GLenum, pname: GLenum, params: *GLint?)
}

/* ---------------------- GL_MESA_framebuffer_swap_xy ---------------------- */

const GL_MESA_framebuffer_swap_xy = 1
const GL_FRAMEBUFFER_SWAP_XY_MESA = 0x8BBD
