const std = @import("std");
const fs = std.fs;
const zigguratt = @import("zigguratt.zig");

const FileImportExport = @import("devices/file_import_export.zig");

pub fn main() !void {
    //Create our allocater
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.detectLeaks();
        if (gpa.deinit() == .leak) @panic("memory leak!!!");
    }
    const allocator = gpa.allocator();

    //Open the bus
    var bus = try zigguratt.openBus();
    defer bus.close();

    //Find the import/export card
    var device = try bus.findDevice(allocator, zigguratt.DeviceType.file_import_export);
    defer device.deinit();

    //Create the card from the device
    var file_import_export = try FileImportExport.createFrom(device, allocator);

    //Reset the transfer of the device
    try file_import_export.resetTransfer();

    //Request a file import
    try file_import_export.requestFileImport();

    var file_info: FileImportExport.FileInfo = undefined;
    defer file_info.deinit();
    while (true) {
        //Try to begin the file import
        file_info = try file_import_export.beginFileImport(allocator);

        //If the status is ok, then we are ready to begin importing
        if (file_info.status == FileImportExport.FileInfo.FileInfoStatus.ok) {
            std.debug.print("Got remote file {s} with size {d}\n", .{ file_info.filename.?, file_info.size.? });
            break;
        }
        //else, deinit the file_info
        else {
            file_info.deinit();
        }
    }

    var file: fs.File = try fs.cwd().createFile(file_info.filename.?, .{});
    defer file.close();

    var full_data = try allocator.alloc(u8, file_info.size.?);
    defer allocator.free(full_data);

    var written: usize = 0;

    var data: []const u8 = &.{0};
    while (data.len != 0) {
        data = try file_import_export.fileImportRead(allocator);
        defer allocator.free(data);

        @memcpy(full_data[written .. written + data.len], data);
        written += data.len;
        // try file.writeAll(data);
        std.debug.print("Transferring... {d}/{d} ({d}%)\r", .{
            // data.len,
            written,
            file_info.size.?,
            written * 100 / file_info.size.?,
        });
    }

    std.debug.print("\nWriting to disk...\n", .{});
    try file.writeAll(full_data);
    std.debug.print("All done!\n", .{});
}
