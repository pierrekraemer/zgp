const Window = @This();

const std = @import("std");
const gl = @import("gl");
const c = @import("../main.zig").c;

const sdl_log = std.log.scoped(.sdl);

const errify = @import("../main.zig").errify;

sdl_window: *c.SDL_Window = undefined,
width: c_int = 1200,
height: c_int = 800,
gl_context: c.SDL_GLContext = undefined,
gl_procs: gl.ProcTable = undefined,

pub fn init(w: *Window) !void {
    const platform: [*:0]const u8 = c.SDL_GetPlatform();
    sdl_log.info("SDL platform: {s}", .{platform});
    sdl_log.info("SDL build time version: {d}.{d}.{d}", .{
        c.SDL_MAJOR_VERSION,
        c.SDL_MINOR_VERSION,
        c.SDL_MICRO_VERSION,
    });
    sdl_log.info("SDL build time revision: {s}", .{c.SDL_REVISION});
    {
        const version = c.SDL_GetVersion();
        sdl_log.info("SDL runtime version: {d}.{d}.{d}", .{
            c.SDL_VERSIONNUM_MAJOR(version),
            c.SDL_VERSIONNUM_MINOR(version),
            c.SDL_VERSIONNUM_MICRO(version),
        });
        const revision: [*:0]const u8 = c.SDL_GetRevision();
        sdl_log.info("SDL runtime revision: {s}", .{revision});
    }

    try errify(c.SDL_SetAppMetadata("zgp", "0.0.0", "zgp"));

    try errify(c.SDL_Init(c.SDL_INIT_VIDEO));
    // We don't need to call 'SDL_Quit()' when using main callbacks.

    try errify(c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, gl.info.version_major));
    try errify(c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, gl.info.version_minor));
    try errify(c.SDL_GL_SetAttribute(
        c.SDL_GL_CONTEXT_PROFILE_MASK,
        switch (gl.info.api) {
            .gl => if (gl.info.profile) |profile| switch (profile) {
                .core => c.SDL_GL_CONTEXT_PROFILE_CORE,
                .compatibility => c.SDL_GL_CONTEXT_PROFILE_COMPATIBILITY,
                else => comptime unreachable,
            } else 0,
            .gles, .glsc => c.SDL_GL_CONTEXT_PROFILE_ES,
        },
    ));
    try errify(c.SDL_GL_SetAttribute(
        c.SDL_GL_CONTEXT_FLAGS,
        if (gl.info.api == .gl and gl.info.version_major >= 3) c.SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG else 0,
    ));

    var nb_displays: c_int = 0;
    const displays = try errify(c.SDL_GetDisplays(&nb_displays));
    if (nb_displays > 0) {
        for (0..@intCast(nb_displays)) |i| {
            const display_name = c.SDL_GetDisplayName(displays[i]);
            sdl_log.info("Display {d}: {s}", .{ i, display_name });
        }
        const display_mode = try errify(c.SDL_GetDesktopDisplayMode(displays[0]));
        w.width = display_mode.*.w - 200;
        w.height = display_mode.*.h;
    } else {
        sdl_log.warn("No display found", .{});
    }
    c.SDL_free(displays);

    w.sdl_window = try errify(c.SDL_CreateWindow("zgp", w.width, w.height, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE));
    errdefer c.SDL_DestroyWindow(w.sdl_window);

    w.gl_context = try errify(c.SDL_GL_CreateContext(w.sdl_window));
    errdefer errify(c.SDL_GL_DestroyContext(w.gl_context)) catch {};

    try errify(c.SDL_GL_MakeCurrent(w.sdl_window, w.gl_context));
    errdefer errify(c.SDL_GL_MakeCurrent(w.sdl_window, null)) catch {};

    try errify(c.SDL_GL_SetSwapInterval(1));

    if (!w.gl_procs.init(c.SDL_GL_GetProcAddress)) return error.GlInitFailed;

    gl.makeProcTableCurrent(&w.gl_procs);
    errdefer gl.makeProcTableCurrent(null);
}

pub fn deinit(w: *Window) void {
    gl.makeProcTableCurrent(null);
    errify(c.SDL_GL_MakeCurrent(w.sdl_window, null)) catch {};
    errify(c.SDL_GL_DestroyContext(w.gl_context)) catch {};
    c.SDL_DestroyWindow(w.sdl_window);
}

pub fn sdlEvent(w: *Window, event: *const c.SDL_Event) void {
    switch (event.type) {
        c.SDL_EVENT_WINDOW_RESIZED => {
            errify(c.SDL_GetWindowSizeInPixels(w.sdl_window, &w.width, &w.height)) catch {};
        },
        else => {},
    }
}
