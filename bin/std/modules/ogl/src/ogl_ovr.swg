#global public

using Swag

/* --------------------------- GL_OVR_multiview ---------------------------- */

const GL_OVR_multiview                                      = 1
const GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_NUM_VIEWS_OVR       = 0x9630
const GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_BASE_VIEW_INDEX_OVR = 0x9632
const GL_MAX_VIEWS_OVR                                      = 0x9631
const GL_FRAMEBUFFER_INCOMPLETE_VIEW_TARGETS_OVR            = 0x9633

#[Extension, Swag.PlaceHolder]
{
    func glFramebufferTextureMultiviewOVR(target: GLenum, attachment: GLenum, texture: GLuint, level: GLint, baseViewIndex: GLint, numViews: GLsizei)
    func glNamedFramebufferTextureMultiviewOVR(framebuffer: GLuint, attachment: GLenum, texture: GLuint, level: GLint, baseViewIndex: GLint, numViews: GLsizei)
}

/* --------------------------- GL_OVR_multiview2 --------------------------- */

const GL_OVR_multiview2 = 1
