# mesa-demos patches

## saphira-no-desktop-gl.patch

Upstream builds every EGL demo against desktop GL (`dependency('gl')`
unconditional) and links the shared util library against GLU
unconditionally. Saphira is headless: mesa builds glx+glvnd disabled,
so no libGL exists, and GLU ships only with a GL provider.

The patch makes desktop GL optional and gates every target that needs
it, leaving `eglinfo` (EGL + glad + util, no GL symbols - verified by
source inspection 2026-10-23) building unconditionally:

- `meson.build`: `dep_gl` becomes `required : false`.
- `src/util/meson.build`: `readtex.c` (needs GLU for
  `gluBuild2DMipmaps`) and `showbuffer.c` (needs GL headers via
  `gl_wrap.h`) join the util library only with a GL provider, and the
  glu link follows the same condition. `glinfo_common`/`trackball`/
  `matrix` always build.
- `src/egl/opengl/meson.build`: all gears (X11/Wayland/KMS/peglgears)
  build only under `dep_gl.found()`; `eglinfo` stays outside the gate.

Consequence: on Saphira the package ships `eglinfo` only. The ES/X11
gears return automatically if a GL provider ever appears (the gate is
presence-based, not a feature cut). `eglkms` stays gated: it includes
`<GL/glext.h>` and needs a KMS node besides.
