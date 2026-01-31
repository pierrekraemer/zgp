const CLIArgs = @This();

const std = @import("std");

var program_name: []const u8 = undefined;

const usage_fmt =
    \\Usage: {s} [-n] [-c] mesh_file1 [mesh_file2 ...]
    \\
    \\Options:
    \\  -n    Normalize the model to fit in a unit cube
    \\  -c    Center the model at the origin
    \\
    \\Arguments:
    \\  mesh_file1 [ mesh_file2 ... ]  List of mesh files
    \\
;

normalize: bool = false,
center: bool = false,
mesh_files: [][:0]u8 = undefined,

pub fn display_usage() void {
    std.debug.print(usage_fmt, .{program_name});
}

const ArgParseError = error{ MissingArgs, InvalidArgs };

pub fn init(argv: [][:0]u8) ArgParseError!CLIArgs {
    program_name = std.fs.path.basename(argv[0]);
    var args: CLIArgs = .{};

    // parse optional arguments i.e. anything that start with a dash '-'
    var optind: usize = 1;
    while (optind < argv.len and argv[optind][0] == '-') : (optind += 1) {
        if (std.mem.eql(u8, argv[optind], "-n")) {
            args.normalize = true;
        } else if (std.mem.eql(u8, argv[optind], "-c")) {
            args.center = true;
        } else if (std.mem.eql(u8, argv[optind], "-B")) {
            // // example of option with a following argument (here a buffer size as a parsed integer)
            // if (optind + 1 >= argv.len) {
            //     display_usage();
            //     return error.MissingArgs;
            // }
            // optind += 1;
            // args.buf_size = std.fmt.parseInt(u32, argv[optind], 10) catch {
            //     display_usage();
            //     std.debug.print("Invalid buffer size: '{s}'\n", .{argv[optind]});
            //     return error.InvalidArgs;
            // };
        } else {
            display_usage();
            std.debug.print("Unknown option: {s}\n", .{argv[optind]});
            return error.InvalidArgs;
        }
    }

    // validate and parse positional arguments
    if (argv.len - optind < 1) {
        display_usage();
        std.debug.print("Missing positional arguments\n", .{});
        return error.MissingArgs;
    }

    args.mesh_files = argv[optind..]; // slice of remaining arguments

    return args;
}
