//! FontInterface is just an adapter interface to use with the system
//! to use any external font library like `TrueType` or `freetype`

pub const InitOptions = struct {
    font_hight: u32,
};

pub fn FontInterface(Font: type) type {
    return struct {
        font: Font,

        pub fn init(options: InitOptions) Font.InitError!@This() {}
    };
}
