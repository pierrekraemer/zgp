const std = @import("std");
const builtin = @import("builtin");
const c = @import("c");

const AppContext = @import("AppContext.zig");

const SurfaceMesh = @import("models/surface/SurfaceMesh.zig");
const PointCloud = @import("models/point/PointCloud.zig");
const IncidenceGraph = @import("models/incidenceGraph/IncidenceGraph.zig");

const SurfaceMeshStore = @import("models/SurfaceMeshStore.zig");
const PointCloudStore = @import("models/PointCloudStore.zig");
const IncidenceGraphStore = @import("models/IncidenceGraphStore.zig");

const Module = @import("modules/Module.zig");

const Window = @import("ui/Window.zig");
const imgui = @import("ui/imgui.zig");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

const sdl_log = std.log.scoped(.sdl);
const zgp_log = std.log.scoped(.zgp);

// TODO: could use a config file with a lib like:
// https://github.com/zig-utils/zig-config

// TODO: use a lib for command-line argument parsing like:
// https://github.com/joegm/flags
// https://github.com/Hejsil/zig-clap
// https://github.com/zig-utils/zig-cli
const CLIArgs = @import("utils/CLIArgs.zig");
var cli_args: CLIArgs = undefined;

/// Io and allocator for the application
var io: std.Io = undefined;
var allocator: std.mem.Allocator = undefined;

/// Main application context
var app_ctx: AppContext = undefined;

fn sdlAppInit(appstate: ?*?*anyopaque, argv: [][*:0]u8) !c.SDL_AppResult {
    _ = appstate;
    _ = argv;

    app_ctx = try .init(io, allocator);
    try app_ctx.wireUp();
    try app_ctx.readArgs(cli_args);

    return c.SDL_APP_CONTINUE;
}

fn sdlAppIterate(appstate: ?*anyopaque) !c.SDL_AppResult {
    _ = appstate;

    if (!try app_ctx.mainUI()) {
        return c.SDL_APP_SUCCESS;
    }
    return c.SDL_APP_CONTINUE;
}

fn sdlAppEvent(appstate: ?*anyopaque, event: *c.SDL_Event) !c.SDL_AppResult {
    _ = appstate;

    switch (event.type) {
        c.SDL_EVENT_QUIT => {
            return c.SDL_APP_SUCCESS;
        },
        c.SDL_EVENT_KEY_DOWN => {
            switch (event.key.key) {
                c.SDLK_ESCAPE => return c.SDL_APP_SUCCESS,
                else => {},
            }
        },
        else => {},
    }
    app_ctx.sdlEvent(event);

    return c.SDL_APP_CONTINUE;
}

fn sdlAppQuit(appstate: ?*anyopaque, result: anyerror!c.SDL_AppResult) void {
    _ = appstate;

    _ = result catch |err| if (err == error.SdlError) {
        sdl_log.err("{s}", .{c.SDL_GetError()});
    };

    imgui.deinit();
    app_ctx.deinit();
}

pub fn main(init: std.process.Init) !u8 {
    var empty_argv: [0:null]?[*:0]u8 = .{};

    io = init.io;
    allocator = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    cli_args = CLIArgs.init(args) catch |err| {
        switch (err) {
            error.MissingArgs => return c.SDL_APP_FAILURE,
            error.InvalidArgs => return c.SDL_APP_FAILURE,
        }
    };

    zgp_log.info("Thread mode: {s}", .{if (builtin.single_threaded) "single-threaded" else "multi-threaded"});

    const status: u8 = @truncate(@as(c_uint, @bitCast(c.SDL_RunApp(@intCast(empty_argv.len), @ptrCast(&empty_argv), sdlMainC, null))));
    return app_err.load() orelse status;
}

fn sdlMainC(argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c_int {
    return c.SDL_EnterAppMainCallbacks(argc, @ptrCast(argv), sdlAppInitC, sdlAppIterateC, sdlAppEventC, sdlAppQuitC);
}

fn sdlAppInitC(appstate: ?*?*anyopaque, argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c.SDL_AppResult {
    return sdlAppInit(appstate.?, @ptrCast(argv.?[0..@intCast(argc)])) catch |err| app_err.store(err);
}

fn sdlAppIterateC(appstate: ?*anyopaque) callconv(.c) c.SDL_AppResult {
    return sdlAppIterate(appstate) catch |err| app_err.store(err);
}

fn sdlAppEventC(appstate: ?*anyopaque, event: ?*c.SDL_Event) callconv(.c) c.SDL_AppResult {
    return sdlAppEvent(appstate, event.?) catch |err| app_err.store(err);
}

fn sdlAppQuitC(appstate: ?*anyopaque, result: c.SDL_AppResult) callconv(.c) void {
    sdlAppQuit(appstate, app_err.load() orelse result);
}

var app_err: ErrorStore = .{};

const ErrorStore = struct {
    const status_not_stored = 0;
    const status_storing = 1;
    const status_stored = 2;

    status: c.SDL_AtomicInt = .{ .value = status_not_stored },
    err: anyerror = undefined,
    trace_index: usize = undefined,
    trace_addrs: [32]usize = undefined,

    fn store(es: *ErrorStore, err: anyerror) c.SDL_AppResult {
        if (c.SDL_CompareAndSwapAtomicInt(&es.status, status_not_stored, status_storing)) {
            es.err = err;
            if (@errorReturnTrace()) |src_trace| {
                es.trace_index = src_trace.index;
                const len = @min(es.trace_addrs.len, src_trace.instruction_addresses.len);
                @memcpy(es.trace_addrs[0..len], src_trace.instruction_addresses[0..len]);
            }
            _ = c.SDL_SetAtomicInt(&es.status, status_stored);
        }
        return c.SDL_APP_FAILURE;
    }

    fn load(es: *ErrorStore) ?anyerror {
        if (c.SDL_GetAtomicInt(&es.status) != status_stored) return null;
        if (@errorReturnTrace()) |dst_trace| {
            dst_trace.index = es.trace_index;
            const len = @min(dst_trace.instruction_addresses.len, es.trace_addrs.len);
            @memcpy(dst_trace.instruction_addresses[0..len], es.trace_addrs[0..len]);
        }
        return es.err;
    }
};
