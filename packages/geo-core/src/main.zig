const builtin = @import("builtin");
const std = @import("std");
const package = @import("package.zig");
const templates = @import("mod.zig");
const types = @import("types.zig");

const allocator = if (builtin.target.cpu.arch.isWasm())
    std.heap.wasm_allocator
else
    std.heap.page_allocator;

const GenerateInput = struct {
    key: []const u8,
    numeric_params: []const templates.schema.NumericParamValue = &.{},
    select_params: []const templates.schema.SelectParamValue = &.{},
    contents: []const InputContent = &.{},
};

const InputContent = struct {
    id: types.ContentId,
    panel_id: types.PanelId,
    type: []const u8,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    rotation: f64 = 0,
    text: []const u8 = "",
    image_url: []const u8 = "",
    focal_x: f64 = 50,
    focal_y: f64 = 50,
    color: []const u8 = "#000000",
    font_size: f64 = 18,
};

var last_result: ?[]u8 = null;
var last_error: ?[]u8 = null;

pub export fn allocate(len: usize) ?[*]u8 {
    const buffer = allocator.alloc(u8, len) catch return null;
    return buffer.ptr;
}

pub export fn deallocate(ptr: [*]u8, len: usize) void {
    allocator.free(ptr[0..len]);
}

pub export fn list_templates() u32 {
    clearLastError();
    const result = serializeTemplates() catch |err| {
        setLastError(err) catch {};
        return 1;
    };

    replaceLastResult(result);
    return 0;
}

pub export fn generate_package(input_ptr: [*]const u8, input_len: usize) u32 {
    clearLastError();
    const input = input_ptr[0..input_len];
    const result = generatePackage(input) catch |err| {
        setLastError(err) catch {};
        return 1;
    };

    replaceLastResult(result);
    return 0;
}

pub export fn get_result_ptr() usize {
    return if (last_result) |buffer| @intFromPtr(buffer.ptr) else 0;
}

pub export fn get_result_len() usize {
    return if (last_result) |buffer| buffer.len else 0;
}

pub export fn free_result() void {
    if (last_result) |buffer| allocator.free(buffer);
    last_result = null;
}

pub export fn get_error_ptr() usize {
    return if (last_error) |buffer| @intFromPtr(buffer.ptr) else 0;
}

pub export fn get_error_len() usize {
    return if (last_error) |buffer| buffer.len else 0;
}

pub export fn free_error() void {
    if (last_error) |buffer| allocator.free(buffer);
    last_error = null;
}

fn serializeTemplates() ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    var writer: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{},
    };

    const descriptors = templates.exportTemplates();
    try writer.beginObject();
    try writer.objectField("templates");
    try writer.beginArray();
    for (descriptors) |descriptor| {
        try writer.beginObject();
        try writer.objectField("key");
        try writer.write(descriptor.key);
        try writer.objectField("label");
        try writer.write(descriptor.label);
        try writer.objectField("package_kind");
        try writer.write(@tagName(descriptor.package_kind));
        try writer.objectField("numeric_params");
        try writer.beginArray();
        for (descriptor.numeric_params) |param| {
            try writer.beginObject();
            try writer.objectField("key");
            try writer.write(param.key);
            try writer.objectField("label");
            try writer.write(param.label);
            try writer.objectField("default_value");
            try writer.write(param.default_value);
            try writer.objectField("min_value");
            try writer.write(param.min_value);
            try writer.objectField("max_value");
            try writer.write(param.max_value);
            try writer.endObject();
        }
        try writer.endArray();
        try writer.objectField("select_params");
        try writer.beginArray();
        for (descriptor.select_params) |param| {
            try writer.beginObject();
            try writer.objectField("key");
            try writer.write(param.key);
            try writer.objectField("label");
            try writer.write(param.label);
            try writer.objectField("default_value");
            try writer.write(param.default_value);
            try writer.objectField("options");
            try writer.beginArray();
            for (param.options) |option| {
                try writer.beginObject();
                try writer.objectField("value");
                try writer.write(option.value);
                try writer.objectField("label");
                try writer.write(option.label);
                try writer.endObject();
            }
            try writer.endArray();
            try writer.endObject();
        }
        try writer.endArray();
        try writer.endObject();
    }
    try writer.endArray();
    try writer.endObject();

    return out.toOwnedSlice();
}

fn generatePackage(input_json: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(GenerateInput, allocator, input_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const instance = try templates.createTemplate(
        allocator,
        parsed.value.key,
        parsed.value.numeric_params,
        parsed.value.select_params,
    );
    defer instance.deinit();
    const contents = try mapInputContents(allocator, parsed.value.contents);
    defer allocator.free(contents);
    try instance.setContents(contents);

    var drawing = try instance.buildDrawing2D(allocator);
    defer drawing.deinit(allocator);

    var preview = try instance.buildPreview3D(allocator);
    defer preview.deinit(allocator);

    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    var writer: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{},
    };

    try writer.beginObject();
    try writer.objectField("template_key");
    try writer.write(parsed.value.key);
    try writer.objectField("drawing_2d");
    try writeDrawing2D(&writer, drawing);
    try writer.objectField("preview_3d");
    try writePreview3D(&writer, preview);
    try writer.endObject();

    return out.toOwnedSlice();
}

fn writeDrawing2D(writer: *std.json.Stringify, drawing: package.Drawing2DResult) !void {
    try writer.beginObject();
    try writer.objectField("panels");
    try writer.beginArray();
    for (drawing.panels) |panel| {
        try writer.beginObject();
        try writer.objectField("panel_id");
        try writer.write(panel.panel_id);
        try writer.objectField("name");
        try writer.write(panel.name);
        try writer.objectField("boundary");
        try writePath2D(writer, panel.boundary);
        try writer.objectField("content_region");
        try writePath2D(writer, panel.content_region);
        try writer.objectField("surface_frame");
        try writeSurfaceFrame2D(writer, panel.surface_frame);
        try writer.objectField("accepts_content");
        try writer.write(panel.accepts_content);
        try writer.endObject();
    }
    try writer.endArray();
    try writer.objectField("linework");
    try writer.beginArray();
    for (drawing.linework) |linework| {
        try writer.beginObject();
        try writer.objectField("role");
        try writer.write(@tagName(linework.role));
        try writer.objectField("stroke_style");
        try writer.write(@tagName(linework.stroke_style));
        try writer.objectField("path");
        try writePath2D(writer, linework.path);
        try writer.endObject();
    }
    try writer.endArray();
    try writer.objectField("contents");
    try writer.beginArray();
    for (drawing.contents) |content| {
        try writeContentPlacement(writer, content);
    }
    try writer.endArray();
    try writer.endObject();
}

fn writePreview3D(writer: *std.json.Stringify, preview: package.Preview3DResult) !void {
    try writer.beginObject();
    try writer.objectField("nodes");
    try writer.beginArray();
    for (preview.nodes) |node| {
        try writer.beginObject();
        try writer.objectField("kind");
        try writer.write(@tagName(node.kind));
        try writer.objectField("parent_index");
        try writer.write(node.parent_index);
        try writer.objectField("panel_id");
        try writer.write(node.panel_id);
        try writer.objectField("hinge_segment_index");
        try writer.write(node.hinge_segment_index);
        try writer.objectField("boundary");
        if (node.boundary) |boundary| {
            try writePath2D(writer, boundary);
        } else {
            try writer.write(null);
        }
        try writer.objectField("surface_frame");
        if (node.surface_frame) |surface_frame| {
            try writeSurfaceFrame2D(writer, surface_frame);
        } else {
            try writer.write(null);
        }
        try writer.objectField("outside_normal");
        if (node.outside_normal) |outside_normal| {
            try writeVec3(writer, outside_normal);
        } else {
            try writer.write(null);
        }
        try writer.objectField("transform");
        try writer.beginObject();
        try writer.objectField("translation");
        try writeVec3(writer, node.transform.translation);
        try writer.objectField("rotation_origin");
        try writeVec3(writer, node.transform.rotation_origin);
        try writer.objectField("rotation_axis");
        try writeVec3(writer, node.transform.rotation_axis);
        try writer.objectField("rotation_rad");
        try writer.write(node.transform.rotation_rad);
        try writer.objectField("scale");
        try writeVec3(writer, node.transform.scale);
        try writer.endObject();
        try writer.endObject();
    }
    try writer.endArray();
    try writer.objectField("contents");
    try writer.beginArray();
    for (preview.contents) |content| {
        try writeContentPlacement(writer, content);
    }
    try writer.endArray();
    try writer.objectField("thickness");
    try writer.write(preview.thickness);
    try writer.endObject();
}

fn writeContentPlacement(
    writer: *std.json.Stringify,
    content: types.PanelContentPlacement,
) !void {
    try writer.beginObject();
    try writer.objectField("id");
    try writer.write(content.id);
    try writer.objectField("panel_id");
    try writer.write(content.panel_id);
    try writer.objectField("transform");
    try writer.beginObject();
    try writer.objectField("position");
    try writeVec2(writer, content.transform.position);
    try writer.objectField("size");
    try writeVec2(writer, content.transform.size);
    try writer.objectField("rotation_rad");
    try writer.write(content.transform.rotation_rad);
    try writer.objectField("space");
    try writer.write(@tagName(content.transform.space));
    try writer.endObject();
    try writer.objectField("z_index");
    try writer.write(content.z_index);
    try writer.objectField("clip_path");
    if (content.clip_path) |clip_path| {
        try writePath2D(writer, clip_path);
    } else {
        try writer.write(null);
    }
    try writer.objectField("surface_frame");
    if (content.surface_frame) |surface_frame| {
        try writeSurfaceFrame2D(writer, surface_frame);
    } else {
        try writer.write(null);
    }
    try writer.objectField("content");
    try writer.beginObject();
    switch (content.content) {
        .image => |image| {
            try writer.objectField("type");
            try writer.write("image");
            try writer.objectField("image_url");
            try writer.write(image.source);
            try writer.objectField("focal_point");
            try writeVec2(writer, image.focal_point);
        },
        .text => |text| {
            try writer.objectField("type");
            try writer.write("text");
            try writer.objectField("text");
            try writer.write(text.text);
            try writer.objectField("font_size");
            try writer.write(text.font_size);
            try writer.objectField("color");
            try writer.write(text.color_hex);
        },
        .shape => |shape| {
            try writer.objectField("type");
            try writer.write("shape");
            try writer.objectField("fill_svg_path");
            try writer.write(shape.fill_svg_path);
        },
        .qr_code => |qr_code| {
            try writer.objectField("type");
            try writer.write("qr_code");
            try writer.objectField("payload");
            try writer.write(qr_code.payload);
        },
        .barcode => |barcode| {
            try writer.objectField("type");
            try writer.write("barcode");
            try writer.objectField("payload");
            try writer.write(barcode.payload);
        },
        .vector_path => |vector_path| {
            try writer.objectField("type");
            try writer.write("vector_path");
            try writer.objectField("path");
            try writePath2D(writer, vector_path.path);
        },
    }
    try writer.endObject();
    try writer.endObject();
}

fn writePath2D(writer: *std.json.Stringify, path: types.Path2D) !void {
    try writer.beginObject();
    try writer.objectField("closed");
    try writer.write(path.closed);
    try writer.objectField("segments");
    try writer.beginArray();
    for (path.segments) |segment| {
        try writer.beginObject();
        switch (segment) {
            .Line => |line| {
                try writer.objectField("kind");
                try writer.write("Line");
                try writer.objectField("from");
                try writeVec2(writer, line.from);
                try writer.objectField("to");
                try writeVec2(writer, line.to);
            },
            .Arc => |arc| {
                try writer.objectField("kind");
                try writer.write("Arc");
                try writer.objectField("center");
                try writeVec2(writer, arc.center);
                try writer.objectField("radius");
                try writer.write(arc.radius);
                try writer.objectField("startAngle");
                try writer.write(arc.startAngle);
                try writer.objectField("endAngle");
                try writer.write(arc.endAngle);
                try writer.objectField("clockwise");
                try writer.write(arc.clockwise);
            },
            .Bezier => |bezier| {
                try writer.objectField("kind");
                try writer.write("Bezier");
                try writer.objectField("p0");
                try writeVec2(writer, bezier.p0);
                try writer.objectField("p1");
                try writeVec2(writer, bezier.p1);
                try writer.objectField("p2");
                try writeVec2(writer, bezier.p2);
                try writer.objectField("p3");
                try writeVec2(writer, bezier.p3);
            },
        }
        try writer.endObject();
    }
    try writer.endArray();
    try writer.endObject();
}

fn writeVec2(writer: *std.json.Stringify, vec: types.Vec2) !void {
    try writer.beginObject();
    try writer.objectField("x");
    try writer.write(vec.x);
    try writer.objectField("y");
    try writer.write(vec.y);
    try writer.endObject();
}

fn writeVec3(writer: *std.json.Stringify, vec: types.Vec3) !void {
    try writer.beginObject();
    try writer.objectField("x");
    try writer.write(vec.x);
    try writer.objectField("y");
    try writer.write(vec.y);
    try writer.objectField("z");
    try writer.write(vec.z);
    try writer.endObject();
}

fn writeSurfaceFrame2D(
    writer: *std.json.Stringify,
    frame: types.SurfaceFrame2D,
) !void {
    try writer.beginObject();
    try writer.objectField("origin");
    try writeVec2(writer, frame.origin);
    try writer.objectField("u_axis");
    try writeVec2(writer, frame.u_axis);
    try writer.objectField("v_axis");
    try writeVec2(writer, frame.v_axis);
    try writer.endObject();
}

fn replaceLastResult(buffer: []u8) void {
    free_result();
    last_result = buffer;
}

fn clearLastError() void {
    free_error();
}

fn setLastError(err: anyerror) !void {
    free_error();
    last_error = try allocator.dupe(u8, @errorName(err));
}

fn mapInputContents(
    allocator_: std.mem.Allocator,
    inputs: []const InputContent,
) ![]types.PanelContentPlacement {
    const placements = try allocator_.alloc(types.PanelContentPlacement, inputs.len);
    for (inputs, 0..) |input, index| {
        placements[index] = .{
            .id = input.id,
            .panel_id = input.panel_id,
            .content = if (std.mem.eql(u8, input.type, "image"))
                .{
                    .image = .{
                        .source = input.image_url,
                        .focal_point = .{ .x = input.focal_x, .y = input.focal_y },
                    },
                }
            else
                .{
                    .text = .{
                        .text = input.text,
                        .font_size = input.font_size,
                        .color_hex = input.color,
                    },
                },
            .transform = .{
                .position = .{ .x = input.x, .y = input.y },
                .size = .{ .x = input.width, .y = input.height },
                .rotation_rad = input.rotation,
                .space = .panel_uv_percent,
            },
        };
    }
    return placements;
}

test "list templates serializes template metadata" {
    const json = try serializeTemplates();
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "folding_carton.simple_two_panel") != null);
}

test "generate package serializes drawing and preview" {
    const input =
        \\{"key":"folding_carton.simple_two_panel","numeric_params":[{"key":"panel_width","value":48},{"key":"fold_angle_rad","value":1.5707963267948966}],"contents":[{"id":1,"panel_id":0,"type":"text","x":10,"y":20,"width":30,"height":15,"rotation":0.1,"text":"Hello","color":"#112233","font_size":16}]}
    ;
    const json = try generatePackage(input);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"drawing_2d\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"preview_3d\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"Hello\"") != null);
}
