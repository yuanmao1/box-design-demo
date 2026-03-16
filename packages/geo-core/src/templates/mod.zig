const std = @import("std");
const package = @import("../package.zig");

pub const schema = @import("schema.zig");

pub const folding_carton = struct {
    pub const simple_two_panel = @import("simple_two_panel.zig");
    pub const four_panel_tube = @import("four_panel_tube.zig");
    pub const restricted_print_panel = @import("restricted_print_panel.zig");
    pub const sector_panel_single = @import("sector_panel_single.zig");
    pub const stateful_mailer_open_ratio = @import("stateful_mailer_open_ratio.zig");
    pub const mailer_box = @import("mailer_box.zig");
};

pub const TemplateInstance = union(enum) {
    simple_two_panel: *folding_carton.simple_two_panel.Instance,
    four_panel_tube: *folding_carton.four_panel_tube.Instance,
    restricted_print_panel: *folding_carton.restricted_print_panel.Instance,
    sector_panel_single: *folding_carton.sector_panel_single.Instance,
    stateful_mailer_open_ratio: *folding_carton.stateful_mailer_open_ratio.Instance,
    mailer_box: *folding_carton.mailer_box.Instance,

    pub fn deinit(self: TemplateInstance) void {
        switch (self) {
            .simple_two_panel => |instance| instance.deinit(),
            .four_panel_tube => |instance| instance.deinit(),
            .restricted_print_panel => |instance| instance.deinit(),
            .sector_panel_single => |instance| instance.deinit(),
            .stateful_mailer_open_ratio => |instance| instance.deinit(),
            .mailer_box => |instance| instance.deinit(),
        }
    }

    pub fn setContents(
        self: TemplateInstance,
        contents: []@import("../types.zig").PanelContentPlacement,
    ) !void {
        return switch (self) {
            .simple_two_panel => |instance| try instance.setContents(contents),
            .four_panel_tube => |instance| try instance.setContents(contents),
            .restricted_print_panel => |instance| try instance.setContents(contents),
            .sector_panel_single => |instance| try instance.setContents(contents),
            .stateful_mailer_open_ratio => |instance| try instance.setContents(contents),
            .mailer_box => |instance| try instance.setContents(contents),
        };
    }

    pub fn buildDrawing2D(
        self: TemplateInstance,
        allocator: std.mem.Allocator,
    ) !package.Drawing2DResult {
        return switch (self) {
            .simple_two_panel => |instance| instance.buildDrawing2D(allocator),
            .four_panel_tube => |instance| instance.buildDrawing2D(allocator),
            .restricted_print_panel => |instance| instance.buildDrawing2D(allocator),
            .sector_panel_single => |instance| instance.buildDrawing2D(allocator),
            .stateful_mailer_open_ratio => |instance| instance.buildDrawing2D(allocator),
            .mailer_box => |instance| instance.buildDrawing2D(allocator),
        };
    }

    pub fn buildPreview3D(
        self: TemplateInstance,
        allocator: std.mem.Allocator,
    ) !package.Preview3DResult {
        return switch (self) {
            .simple_two_panel => |instance| instance.buildPreview3D(allocator),
            .four_panel_tube => |instance| instance.buildPreview3D(allocator),
            .restricted_print_panel => |instance| instance.buildPreview3D(allocator),
            .sector_panel_single => |instance| instance.buildPreview3D(allocator),
            .stateful_mailer_open_ratio => |instance| instance.buildPreview3D(allocator),
            .mailer_box => |instance| instance.buildPreview3D(allocator),
        };
    }
};

pub fn exportTemplates() []const schema.TemplateDescriptor {
    return &.{
        folding_carton.simple_two_panel.descriptor,
        folding_carton.four_panel_tube.descriptor,
        folding_carton.restricted_print_panel.descriptor,
        folding_carton.sector_panel_single.descriptor,
        folding_carton.stateful_mailer_open_ratio.descriptor,
        folding_carton.mailer_box.descriptor,
    };
}

pub fn createTemplate(
    allocator: std.mem.Allocator,
    key: []const u8,
    numeric_params: []const schema.NumericParamValue,
) !TemplateInstance {
    if (std.mem.eql(u8, key, folding_carton.simple_two_panel.descriptor.key)) {
        return .{
            .simple_two_panel = try folding_carton.simple_two_panel.create(
                allocator,
                numeric_params,
            ),
        };
    }
    if (std.mem.eql(u8, key, folding_carton.four_panel_tube.descriptor.key)) {
        return .{
            .four_panel_tube = try folding_carton.four_panel_tube.create(
                allocator,
                numeric_params,
            ),
        };
    }
    if (std.mem.eql(u8, key, folding_carton.restricted_print_panel.descriptor.key)) {
        return .{
            .restricted_print_panel = try folding_carton.restricted_print_panel.create(
                allocator,
                numeric_params,
            ),
        };
    }
    if (std.mem.eql(u8, key, folding_carton.sector_panel_single.descriptor.key)) {
        return .{
            .sector_panel_single = try folding_carton.sector_panel_single.create(
                allocator,
                numeric_params,
            ),
        };
    }
    if (std.mem.eql(u8, key, folding_carton.stateful_mailer_open_ratio.descriptor.key)) {
        return .{
            .stateful_mailer_open_ratio = try folding_carton.stateful_mailer_open_ratio.create(
                allocator,
                numeric_params,
            ),
        };
    }
    if (std.mem.eql(u8, key, folding_carton.mailer_box.descriptor.key)) {
        return .{
            .mailer_box = try folding_carton.mailer_box.create(
                allocator,
                numeric_params,
            ),
        };
    }
    return error.UnknownTemplate;
}
