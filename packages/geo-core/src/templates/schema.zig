const package = @import("../package.zig");

pub const NumericParamDef = struct {
    key: []const u8,
    label: []const u8,
    default_value: f64,
    min_value: ?f64 = null,
    max_value: ?f64 = null,
};

pub const NumericParamValue = struct {
    key: []const u8,
    value: f64,
};

pub const SelectOptionDef = struct {
    value: []const u8,
    label: []const u8,
};

pub const SelectParamDef = struct {
    key: []const u8,
    label: []const u8,
    default_value: []const u8,
    options: []const SelectOptionDef,
};

pub const SelectParamValue = struct {
    key: []const u8,
    value: []const u8,
};

pub const TemplateDescriptor = struct {
    key: []const u8,
    label: []const u8,
    package_kind: package.PackageKind,
    numeric_params: []const NumericParamDef,
    select_params: []const SelectParamDef = &.{},
};
