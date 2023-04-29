const std = @import("std");
const zigguratt = @import("zigguratt.zig");

const FileImportExport = @import("devices/file_import_export.zig");

pub fn main() !void {
    //Create our allocater
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.detectLeaks();
        if (gpa.deinit() == .leak) @panic("memory leak!!!");
    }
    var allocator = gpa.allocator();

    //Open the bus
    var bus = try zigguratt.openBus();
    defer bus.close();

    //Find the import/export card
    var device = try bus.findDevice(allocator, zigguratt.DeviceType.file_import_export);
    defer device.deinit();
    // std.debug.print("found device id {s}, with type {s}\n", .{ device.id, @tagName(device.type) });

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
}
