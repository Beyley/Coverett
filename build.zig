const std = @import("std");
const Self = @This();
const CrossTarget = std.zig.CrossTarget;

pub fn createCJson(b: *std.Build, target: CrossTarget, optimize: std.builtin.Mode, comptime shared: bool) *std.build.CompileStep {
    const cjson_options = .{
        .name = "cjson",
        .target = target,
        .optimize = optimize,
    };

    const cjson: *std.build.CompileStep = if (shared) b.addSharedLibrary(cjson_options) else b.addStaticLibrary(cjson_options);

    cjson.linkLibC();
    cjson.addCSourceFiles(cjson_srcs, &.{});

    return cjson;
}

pub fn createCoverett(b: *std.Build, target: CrossTarget, optimize: std.builtin.Mode, comptime shared: bool) *std.build.CompileStep {
    var cjson = createCJson(b, target, optimize, false);

    const coverett_options = .{
        .name = "coverett",
        .target = target,
        .optimize = optimize,
    };

    const coverett: *std.build.CompileStep = if (shared) b.addSharedLibrary(coverett_options) else b.addStaticLibrary(coverett_options);
    coverett.linkLibC();
    coverett.linkLibrary(cjson);
    coverett.addCSourceFiles(coverett_srcs, &.{});
    return coverett;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var static_coverett = createCoverett(b, target, optimize, false);
    //Install the static library version of coverett
    b.installArtifact(static_coverett);
    //Install a shared library version of coverett
    b.installArtifact(createCoverett(b, target, optimize, true));

    var fimexu: *std.Build.CompileStep = b.addExecutable(.{ .name = "fimexu", .target = target, .optimize = optimize });
    fimexu.linkLibrary(static_coverett);
    fimexu.linkLibC();
    fimexu.addCSourceFiles(fimexu_srcs, &.{});
    b.installArtifact(fimexu);

    var ldevmet: *std.Build.CompileStep = b.addExecutable(.{ .name = "ldevmet", .target = target, .optimize = optimize });
    ldevmet.linkLibrary(static_coverett);
    ldevmet.linkLibC();
    ldevmet.addCSourceFiles(ldevmet_srcs, &.{});
    b.installArtifact(ldevmet);

    var lshldev: *std.Build.CompileStep = b.addExecutable(.{ .name = "lshldev", .target = target, .optimize = optimize });
    lshldev.linkLibrary(static_coverett);
    lshldev.linkLibC();
    lshldev.addCSourceFiles(lshldev_srcs, &.{});
    b.installArtifact(lshldev);

    var redstone: *std.Build.CompileStep = b.addExecutable(.{ .name = "redstone", .target = target, .optimize = optimize });
    redstone.linkLibrary(static_coverett);
    redstone.linkLibC();
    redstone.addCSourceFiles(redstone_srcs, &.{});
    b.installArtifact(redstone);

    var seplay: *std.Build.CompileStep = b.addExecutable(.{ .name = "seplay", .target = target, .optimize = optimize });
    seplay.linkLibrary(static_coverett);
    seplay.linkLibC();
    seplay.addCSourceFiles(seplay_srcs, &.{});
    b.installArtifact(seplay);
}

const coverett_srcs = &.{
    root_path ++ "coverett.c",
    root_path ++ "coverett-private.c",
    root_path ++ "devices/block_operations.c",
    root_path ++ "devices/energy_storage.c",
    root_path ++ "devices/file_import_export.c",
    root_path ++ "devices/inventory_operations.c",
    root_path ++ "devices/item_handler.c",
    root_path ++ "devices/redstone.c",
    root_path ++ "devices/robot.c",
    root_path ++ "devices/sound.c",
};

const fimexu_srcs = &.{
    root_path ++ "fimexu.c",
};

const ldevmet_srcs = &.{
    root_path ++ "ldevmet.c",
};

const lshldev_srcs = &.{
    root_path ++ "lshldev.c",
};

const redstone_srcs = &.{
    root_path ++ "redstone.c",
};

const seplay_srcs = &.{
    root_path ++ "seplay.c",
};

const cjson_srcs = &.{
    root_path ++ "cJSON/cJSON.c",
};

fn root() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

const root_path = root() ++ "/";
