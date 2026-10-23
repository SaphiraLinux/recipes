# nvidia-open-7.1.5 patches

Same gate as every nvidia-open line (7.2.2, 7.2.3, 7.3-rc1, 7.3
carry the identical file; each recipe passes it to the kmod helper).

| File | Why |
|---|---|
| `0001-gate-fbdev-on-kconfig.patch` | Gate `NV_DRM_FBDEV_AVAILABLE` on `CONFIG_DRM_FBDEV_EMULATION`: header-only detection caused an implicit-declaration failure. Without it the module does not compile. |
