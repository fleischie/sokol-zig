const std = @import("std");
const builtin = @import("builtin");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;
const CrossTarget = @import("std").zig.CrossTarget;
const Mode = std.builtin.Mode;

const DisplayServer = struct {
    use_wayland: bool,
    use_x11: bool,
};

// build sokol into a static library
pub fn buildSokol(b: *Builder, target: CrossTarget, mode: Mode, comptime prefix_path: []const u8, display_server: DisplayServer) *LibExeObjStep {
    const lib = b.addStaticLibrary("sokol", null);
    lib.setBuildMode(mode);
    lib.setTarget(target);
    lib.linkLibC();
    const sokol_path = prefix_path ++ "src/sokol/c/";
    const csources = [_][]const u8 {
        "sokol_app.c",
        "sokol_gfx.c",
        "sokol_time.c",
        "sokol_audio.c",
        "sokol_gl.c",
        "sokol_debugtext.c",
        "sokol_shape.c",
    };
    if (lib.target.isDarwin()) {
        inline for (csources) |csrc| {
            lib.addCSourceFile(sokol_path ++ csrc, &[_][]const u8{"-ObjC", "-DIMPL"});
        }
        lib.linkFramework("MetalKit");
        lib.linkFramework("Metal");
        lib.linkFramework("Cocoa");
        lib.linkFramework("QuartzCore");
        lib.linkFramework("AudioToolbox");
    } else {
        inline for (csources) |csrc| {
            lib.addCSourceFile(sokol_path ++ csrc, &[_][]const u8{"-DIMPL"});
        }
        if (lib.target.isLinux()) {
            lib.linkSystemLibrary("GL");
            lib.linkSystemLibrary("asound");
            if (display_server.use_x11) {
                lib.linkSystemLibrary("X11");
                lib.linkSystemLibrary("Xi");
                lib.linkSystemLibrary("Xcursor");
            }
            if (display_server.use_wayland) {
                lib.linkSystemLibrary("wayland-client");
                lib.linkSystemLibrary("wayland-cursor");
                lib.linkSystemLibrary("wayland-egl");
                lib.linkSystemLibrary("egl");
                lib.linkSystemLibrary("xkbcommon");
            }
        }
        else if (lib.target.isWindows()) {
            lib.linkSystemLibrary("kernel32");
            lib.linkSystemLibrary("user32");
            lib.linkSystemLibrary("gdi32");
            lib.linkSystemLibrary("ole32");
            lib.linkSystemLibrary("d3d11");
            lib.linkSystemLibrary("dxgi");
        }
    }
    return lib;
}

// build one of the example exes
fn buildExample(b: *Builder, target: CrossTarget, mode: Mode, sokol: *LibExeObjStep, comptime name: []const u8, display_server: DisplayServer) void {
    const e = b.addExecutable(name, "src/examples/" ++ name ++ ".zig");
    e.setBuildMode(mode);
    e.setTarget(target);
    if (!display_server.use_x11) {
        e.defineCMacro("SOKOL_DISABLE_X11", null);
    }
    if (!display_server.use_wayland) {
        e.defineCMacro("SOKOL_DISABLE_WAYLAND", null);
    }
    e.linkLibrary(sokol);
    e.addPackagePath("sokol", "src/sokol/sokol.zig");
    e.install();
    b.step("run-" ++ name, "Run " ++ name).dependOn(&e.run().step);
}

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const use_wayland = b.option(bool, "wayland", "Compile with wayland-support (default: false)") orelse false;
    const use_x11 = b.option(bool, "x11", "Compile with x11-support (default: true)") orelse true;
    const display_server = DisplayServer{ .use_wayland = use_wayland, .use_x11 = use_x11 };

    const sokol = buildSokol(b, target, mode, "", display_server);
    const examples = .{
        "clear",
        "triangle",
        "quad",
        "bufferoffsets",
        "cube",
        "noninterleaved",
        "texcube",
        "blend",
        "offscreen",
        "instancing",
        "mrt",
        "saudio",
        "sgl",
        "sgl-context",
        "sgl-points",
        "debugtext",
        "debugtext-print",
        "debugtext-userfont",
        "shapes"
    };
    inline for (examples) |example| {
        buildExample(b, target, mode, sokol, example, display_server);
    }
    buildShaders(b);
}

// a separate step to compile shaders, expects the shader compiler in ../sokol-tools-bin/
fn buildShaders(b: *Builder) void {
    const sokol_tools_bin_dir = "../sokol-tools-bin/bin/";
    const shaders_dir = "src/examples/shaders/";
    const shaders = .{
        "bufferoffsets.glsl",
        "cube.glsl",
        "instancing.glsl",
        "mrt.glsl",
        "noninterleaved.glsl",
        "offscreen.glsl",
        "quad.glsl",
        "shapes.glsl",
        "texcube.glsl",
        "blend.glsl",
    };
    const optional_shdc: ?[:0]const u8 = comptime switch (builtin.os.tag) {
        .windows => "win32/sokol-shdc.exe",
        .linux => "linux/sokol-shdc",
        .macos => if (builtin.cpu.arch.isX86()) "osx/sokol-shdc" else "osx_arm64/sokol-shdc",
        else => null,
    };
    if (optional_shdc == null) {
        std.log.warn("unsupported host platform, skipping shader compiler step", .{});
        return;
    }
    const shdc_path = sokol_tools_bin_dir ++ optional_shdc.?;
    const shdc_step = b.step("shaders", "Compile shaders (needs ../sokol-tools-bin)");
    inline for (shaders) |shader| {
        const cmd = b.addSystemCommand(&.{
            shdc_path,
            "-i", shaders_dir ++ shader,
            "-o", shaders_dir ++ shader ++ ".zig",
            "-l", "glsl330:metal_macos:hlsl4",
            "-f", "sokol_zig"
        });
        shdc_step.dependOn(&cmd.step);
    }
}
