const compiled_spec = @import("compiled_spec.zig");
const rounded_tuck_carton_spec = @import("data/spec/rounded_tuck_carton_spec.zig");

const Generated = compiled_spec.defineTemplate(rounded_tuck_carton_spec.spec);

pub const descriptor = Generated.descriptor;
pub const spec = Generated.spec;
pub const Instance = Generated.Instance;
pub const create = Generated.create;
