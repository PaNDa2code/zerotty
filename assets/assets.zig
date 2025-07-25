pub const fonts = struct {
    pub const @"FiraCodeNerdFontMono-Regular.ttf" = @embedFile("fonts/FiraCodeNerdFontMono-Regular.ttf"); 
    pub const @"FiraCodeNerdFontMono-Bold.ttf" = @embedFile("fonts/FiraCodeNerdFontMono-Bold.ttf"); 
};

pub const icons = struct {
    pub const @"logo.ico" = @embedFile("logo.ico");
};

pub const shaders = struct {
    pub const cell_vert = @embedFile("cell.vert.spv");
    pub const cell_frag = @embedFile("cell.frag.spv");
};
