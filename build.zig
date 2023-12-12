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
    cjson.addCSourceFiles(.{ .files = cjson_srcs });

    return cjson;
}

pub fn createCoverett(b: *std.Build, target: CrossTarget, optimize: std.builtin.Mode, comptime shared: bool) *std.build.CompileStep {
    const cjson = createCJson(b, target, optimize, false);

    const coverett_options = .{
        .name = "coverett",
        .target = target,
        .optimize = optimize,
    };

    const coverett: *std.build.CompileStep = if (shared) b.addSharedLibrary(coverett_options) else b.addStaticLibrary(coverett_options);
    coverett.linkLibC();
    coverett.linkLibrary(cjson);
    coverett.addCSourceFiles(.{ .files = coverett_srcs });
    return coverett;
}

pub fn createZigguratt(b: *std.Build, target: CrossTarget, optimize: std.builtin.Mode, comptime shared: bool) *std.build.CompileStep {
    const zigguratt_options = .{
        .name = "zigguratt",
        .optimize = optimize,
        .target = target,
        .root_source_file = .{ .path = "src/zigguratt.zig" },
    };

    const zigguratt: *std.build.CompileStep = if (shared) b.addSharedLibrary(zigguratt_options) else b.addStaticLibrary(zigguratt_options);
    zigguratt.linkLibC();

    return zigguratt;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const static_coverett = createCoverett(b, target, optimize, false);
    //Install the static library version of coverett
    b.installArtifact(static_coverett);
    //Install a shared library version of coverett
    b.installArtifact(createCoverett(b, target, optimize, true));

    const zigguratt = createZigguratt(b, target, optimize, false);
    b.installArtifact(zigguratt);

    var zimexu: *std.Build.CompileStep = b.addExecutable(std.build.ExecutableOptions{
        .name = "zimexu",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/zimexu.zig" },
    });
    zimexu.linkLibC();
    b.installArtifact(zimexu);

    var fimexu: *std.Build.CompileStep = b.addExecutable(.{ .name = "fimexu", .target = target, .optimize = optimize });
    fimexu.linkLibrary(static_coverett);
    fimexu.linkLibC();
    fimexu.addCSourceFiles(.{ .files = fimexu_srcs });
    b.installArtifact(fimexu);

    var ldevmet: *std.Build.CompileStep = b.addExecutable(.{ .name = "ldevmet", .target = target, .optimize = optimize });
    ldevmet.linkLibrary(static_coverett);
    ldevmet.linkLibC();
    ldevmet.addCSourceFiles(.{ .files = ldevmet_srcs });
    b.installArtifact(ldevmet);

    var lshldev: *std.Build.CompileStep = b.addExecutable(.{ .name = "lshldev", .target = target, .optimize = optimize });
    lshldev.linkLibrary(static_coverett);
    lshldev.linkLibC();
    lshldev.addCSourceFiles(.{ .files = lshldev_srcs });
    b.installArtifact(lshldev);

    // var redstone: *std.Build.CompileStep = b.addExecutable(.{ .name = "redstone", .target = target, .optimize = optimize });
    // redstone.linkLibrary(static_coverett);
    // redstone.linkLibC();
    // redstone.addCSourceFiles(.{ .files = redstone_srcs });
    // b.installArtifact(redstone);
    var redstone = b.addExecutable(.{
        .name = "redstone",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/redstone.zig" },
    });
    redstone.linkLibC();
    b.installArtifact(redstone);

    var seplay: *std.Build.CompileStep = b.addExecutable(.{ .name = "seplay", .target = target, .optimize = optimize });
    seplay.linkLibrary(static_coverett);
    seplay.linkLibC();
    seplay.addCSourceFiles(.{ .files = seplay_srcs });
    b.installArtifact(seplay);

    var lsitems: *std.Build.CompileStep = b.addExecutable(.{ .name = "lsitems", .target = target, .optimize = optimize });
    lsitems.linkLibrary(static_coverett);
    lsitems.linkLibC();
    lsitems.addCSourceFiles(.{ .files = lsitems_srcs });
    b.installArtifact(lsitems);
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

const lsitems_srcs = &.{
    root_path ++ "lsitems.c",
};

const cjson_srcs = &.{
    root_path ++ "cJSON/cJSON.c",
};

fn root() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

const root_path = root() ++ "/";
