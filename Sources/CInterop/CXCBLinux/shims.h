#ifndef CXCBLINUX_SHIMS_H
#define CXCBLINUX_SHIMS_H

// Include XCB headers
#include <xcb/xcb.h>
#include <xcb/xproto.h>
#include <xcb/randr.h>
#include <xcb/xinput.h>

// Include XCB utility headers
#include <xcb/xcb_keysyms.h>

// Include XKB headers
#include <xcb/xkb.h>
#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-x11.h>

// Helper functions for XCB API that are difficult to use from Swift

/**
 * Helper to check if an XCB connection has an error.
 * Returns the error code, or 0 if no error.
 */
static inline int xcb_connection_has_error_shim(xcb_connection_t *connection) {
    return xcb_connection_has_error(connection);
}

/**
 * Helper to get the file descriptor for an XCB connection.
 * Useful for select()/poll() integration.
 */
static inline int xcb_get_file_descriptor_shim(xcb_connection_t *connection) {
    return xcb_get_file_descriptor(connection);
}

/**
 * Helper to flush the XCB connection.
 * Returns > 0 on success, <= 0 on error.
 */
static inline int xcb_flush_shim(xcb_connection_t *connection) {
    return xcb_flush(connection);
}

/**
 * Helper to get the setup info from an XCB connection.
 */
static inline const xcb_setup_t* xcb_get_setup_shim(xcb_connection_t *connection) {
    return xcb_get_setup(connection);
}

/**
 * Helper to get screen iterator from setup.
 */
static inline xcb_screen_iterator_t xcb_setup_roots_iterator_shim(const xcb_setup_t *setup) {
    return xcb_setup_roots_iterator(setup);
}

/**
 * Helper to extract event response type (strips off high bit for errors).
 */
static inline uint8_t xcb_event_response_type_shim(xcb_generic_event_t *event) {
    return event->response_type & 0x7f;
}

/**
 * Helper to check if an event is an error (high bit set).
 */
static inline int xcb_event_is_error_shim(xcb_generic_event_t *event) {
    return (event->response_type & 0x80) != 0;
}

#endif // CXCBLINUX_SHIMS_H
