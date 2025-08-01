pub const fonts = struct {
    pub const @"FiraCodeNerdFontMono-Regular.ttf" = @embedFile("fonts/FiraCodeNerdFontMono-Regular.ttf"); 
    pub const @"FiraCodeNerdFontMono-Bold.ttf" = @embedFile("fonts/FiraCodeNerdFontMono-Bold.ttf"); 
};

pub const icons = struct {
    pub const @"logo.ico" = @embedFile("icons/logo.ico");
    pub const @"logo_16x16.png" = @embedFile("icons/logo_16x16.png");
    pub const @"logo_32x32.png" = @embedFile("icons/logo_32x32.png");
    pub const @"logo_48x48.png" = @embedFile("icons/logo_48x48.png");
};

pub const shaders = struct {
    pub const cell_vert = @embedFile("cell.vert.spv");
    pub const cell_frag = @embedFile("cell.frag.spv");
};
