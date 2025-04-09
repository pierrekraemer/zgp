fn TypeIdContainer(T: type) type {
    return struct {
        // dummy struct declaration (static) whose type depends on T
        var id: *const T = undefined;
    };
}

pub fn typeId(T: type) *const anyopaque {
    return @ptrCast(&TypeIdContainer(T).id);
}
