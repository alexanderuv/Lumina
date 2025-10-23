#ifndef LUMINA_WAYLAND_CLIENT_SHIM_H
#define LUMINA_WAYLAND_CLIENT_SHIM_H

// Core Wayland client
#include <wayland-client.h>
#include <wayland-client-protocol.h>

// Wayland EGL for GPU-accelerated rendering (SDL/GLFW pattern)
#include <wayland-egl.h>

// XKB for keyboard handling
#include <xkbcommon/xkbcommon.h>

// Wayland extension protocols (GLFW pattern)
#include "xdg-shell-client-protocol.h"
#include "viewporter-client-protocol.h"
#include "pointer-constraints-unstable-v1-client-protocol.h"
#include "relative-pointer-unstable-v1-client-protocol.h"
#include "xdg-decoration-unstable-v1-client-protocol.h"

// System headers
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/select.h>
#include <sys/syscall.h>
#include <errno.h>
#include <stdio.h>
#include <dlfcn.h>

// Forward declarations for dynamic libdecor loading (GLFW pattern)
// These allow us to use libdecor types without requiring compile-time dependency
struct libdecor;
struct libdecor_frame;
struct libdecor_state;
struct libdecor_configuration;

enum libdecor_error {
    LIBDECOR_ERROR_COMPOSITOR_INCOMPATIBLE,
    LIBDECOR_ERROR_INVALID_FRAME_CONFIGURATION,
};

struct libdecor_interface {
    void (*error)(struct libdecor*, enum libdecor_error, const char*);
};

struct libdecor_frame_interface {
    void (*configure)(struct libdecor_frame*, struct libdecor_configuration*, void*);
    void (*close)(struct libdecor_frame*, void*);
    void (*commit)(struct libdecor_frame*, void*);
    void (*dismiss_popup)(struct libdecor_frame*, const char*, void*);
};

enum libdecor_window_state {
    LIBDECOR_WINDOW_STATE_NONE = 0,
    LIBDECOR_WINDOW_STATE_ACTIVE = 1,
    LIBDECOR_WINDOW_STATE_MAXIMIZED = 2,
    LIBDECOR_WINDOW_STATE_FULLSCREEN = 4,
};

enum libdecor_capabilities {
    LIBDECOR_ACTION_MOVE = 1,
    LIBDECOR_ACTION_RESIZE = 2,
    LIBDECOR_ACTION_MINIMIZE = 4,
    LIBDECOR_ACTION_FULLSCREEN = 8,
    LIBDECOR_ACTION_CLOSE = 16,
};

// C helper for memfd_create (syscall not available in Swift)
static inline int lumina_memfd_create(const char *name, unsigned int flags) {
    #ifdef __NR_memfd_create
    return (int)syscall(__NR_memfd_create, name, flags);
    #else
    errno = ENOSYS;
    return -1;
    #endif
}

// Helper functions to get Wayland interface pointers
// These are necessary because Swift cannot take the address of C global constants
static inline const struct wl_interface* lumina_wl_compositor_interface(void) {
    return &wl_compositor_interface;
}

static inline const struct wl_interface* lumina_wl_shm_interface(void) {
    return &wl_shm_interface;
}

static inline const struct wl_interface* lumina_wl_seat_interface(void) {
    return &wl_seat_interface;
}

static inline const struct wl_interface* lumina_wl_output_interface(void) {
    return &wl_output_interface;
}

static inline const struct wl_interface* lumina_wl_subcompositor_interface(void) {
    return &wl_subcompositor_interface;
}

static inline const struct wl_interface* lumina_wl_data_device_manager_interface(void) {
    return &wl_data_device_manager_interface;
}

// Extension protocol interfaces (GLFW pattern)
static inline const struct wl_interface* lumina_xdg_wm_base_interface(void) {
    return &xdg_wm_base_interface;
}

static inline const struct wl_interface* lumina_wp_viewporter_interface(void) {
    return &wp_viewporter_interface;
}

static inline const struct wl_interface* lumina_zwp_pointer_constraints_v1_interface(void) {
    return &zwp_pointer_constraints_v1_interface;
}

static inline const struct wl_interface* lumina_zwp_relative_pointer_manager_v1_interface(void) {
    return &zwp_relative_pointer_manager_v1_interface;
}

static inline const struct wl_interface* lumina_zxdg_decoration_manager_v1_interface(void) {
    return &zxdg_decoration_manager_v1_interface;
}

// User data struct for libdecor window callbacks
// This is a plain C struct that can be safely allocated and passed to C APIs
// SDL/GLFW pattern: Store EGL window pointer for resize in configure callback
typedef struct {
    uint64_t window_id_high;
    uint64_t window_id_low;
    float current_width;
    float current_height;
    struct wl_egl_window* egl_window;  // EGL window for resizing (SDL pattern)
    struct wl_surface* surface;         // Surface for damage/commit (SDL pattern)
    struct wl_shm* shm;                 // Shared memory for buffer creation
    struct wl_compositor* compositor;   // Compositor for region creation
    _Bool configured;                   // GLFW pattern: Track if configure callback received
} LuminaWindowUserData;

// C helper to initialize libdecor_frame_interface
// This ensures proper initialization without Swift struct layout issues
static inline struct libdecor_frame_interface* lumina_alloc_frame_interface(
    void (*configure)(struct libdecor_frame*, struct libdecor_configuration*, void*),
    void (*close)(struct libdecor_frame*, void*),
    void (*commit)(struct libdecor_frame*, void*)
) {
    fprintf(stderr, "[C Helper] ENTRY: lumina_alloc_frame_interface called\n");
    fflush(stderr);
    struct libdecor_frame_interface *iface = calloc(1, sizeof(struct libdecor_frame_interface));
    if (iface) {
        iface->configure = configure;
        iface->close = close;
        iface->commit = commit;
        iface->dismiss_popup = NULL;
        printf("[C Helper] Allocated frame interface at %p\n", iface);
        printf("[C Helper]   configure = %p\n", iface->configure);
        printf("[C Helper]   close = %p\n", iface->close);
        printf("[C Helper]   commit = %p\n", iface->commit);
        fflush(stdout);
    }
    return iface;
}

static inline void lumina_free_frame_interface(struct libdecor_frame_interface *iface) {
    free(iface);
}

// C helper to allocate and initialize libdecor_interface
// This is needed because libdecor expects at minimum an error callback
static inline struct libdecor_interface* lumina_alloc_libdecor_interface(
    void (*error)(struct libdecor*, enum libdecor_error, const char*)
) {
    struct libdecor_interface *iface = calloc(1, sizeof(struct libdecor_interface));
    if (iface) {
        iface->error = error;
    }
    return iface;
}

static inline void lumina_free_libdecor_interface(struct libdecor_interface *iface) {
    free(iface);
}

#endif /* LUMINA_WAYLAND_CLIENT_SHIM_H */
