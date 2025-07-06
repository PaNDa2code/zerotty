const std = @import("std");
const builtin = @import("builtin");

const freetype = @import("freetype");

const D3D11Renderer = @This();

const pixel_shader_source = @embedFile("shaders/pixel.hlsl");
const vertex_shader_source = @embedFile("shaders/vertex.hlsl");

const ColorRGBA = @import("../common.zig").ColorRGBA;

const Vertex2D = struct { x: f32, y: f32 };

const Allocator = std.mem.Allocator;

const win32 = @import("win32");
const foundation = win32.foundation;
const d3d11 = win32.graphics.direct3d11;
const dxgi = win32.graphics.dxgi;
const d3d = win32.graphics.direct3d;
const fxc = win32.graphics.direct3d.fxc;
const dxc = win32.graphics.direct3d.dxc;
const hlsl = win32.graphics.hlsl;

const DxgiDebugInterface = @import("DxgiDebugInterface.zig");
const Window = @import("../../window/root.zig").Window;

const HWND = foundation.HWND;
const ID3D11Device = d3d11.ID3D11Device;
const ID3D11DeviceContext = d3d11.ID3D11DeviceContext;
const ID3D11RenderTargetView = d3d11.ID3D11RenderTargetView;
const ID3D11VertexShader = d3d11.ID3D11VertexShader;
const ID3D11PixelShader = d3d11.ID3D11PixelShader;
const IDXGIInfoQueue = dxgi.IDXGIInfoQueue;
const IDXGISwapChain = dxgi.IDXGISwapChain;
const ID3DBlob = d3d.ID3DBlob;

device: *ID3D11Device = undefined,
context: *ID3D11DeviceContext = undefined,
swap_chain: *IDXGISwapChain = undefined,
render_target_view: *ID3D11RenderTargetView = undefined,
vertex_shader: *ID3D11VertexShader = undefined,
pixel_shader: *ID3D11PixelShader = undefined,

vertex_shader_blob: *ID3DBlob = undefined,
pixel_shader_blob: *ID3DBlob = undefined,

dxdi: if (builtin.mode == .Debug) DxgiDebugInterface else void = undefined,

// TODO: Replace manual HRESULT checks with proper Zig error unions and error sets when supported.
pub fn init(window: *Window, _: Allocator) !D3D11Renderer {
    var self: D3D11Renderer = .{};

    const sd = dxgi.DXGI_SWAP_CHAIN_DESC{
        .BufferDesc = .{
            .Format = .B8G8R8A8_UNORM,
            .Scaling = .UNSPECIFIED,
            .ScanlineOrdering = .UNSPECIFIED,
            .RefreshRate = .{
                .Denominator = 0,
                .Numerator = 0,
            },
            .Height = 0,
            .Width = 0,
        },
        .BufferUsage = dxgi.DXGI_USAGE_RENDER_TARGET_OUTPUT,
        .BufferCount = 1,
        .OutputWindow = window.hwnd,
        .Flags = 0,
        .SwapEffect = .DISCARD,
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .Windowed = 1,
    };

    var hresult: i32 = 0;

    self.dxdi = try DxgiDebugInterface.init(@ptrCast(self.device));
    self.dxdi.set();
    errdefer self.dxdi.deinit();

    hresult = d3d11.D3D11CreateDeviceAndSwapChain(
        null,
        .HARDWARE,
        null,
        .{ .DEBUG = if (builtin.mode == .Debug) 1 else 0 },
        null,
        0,
        d3d11.D3D11_SDK_VERSION,
        &sd,
        &self.swap_chain,
        &self.device,
        null,
        &self.context,
    );

    try self.dxdi.DxgiCheckHresult(hresult);

    errdefer {
        _ = self.swap_chain.IUnknown.Release();
        _ = self.context.IUnknown.Release();
        _ = self.device.IUnknown.Release();
    }

    var backBuffer: *d3d11.ID3D11Resource = undefined;

    hresult = self.swap_chain.GetBuffer(0, d3d11.IID_ID3D11Resource, @ptrCast(&backBuffer));

    try self.dxdi.DxgiCheckHresult(hresult);

    defer _ = backBuffer.IUnknown.Release();

    hresult = self.device.CreateRenderTargetView(
        backBuffer,
        null,
        &self.render_target_view,
    );

    try self.dxdi.DxgiCheckHresult(hresult);

    errdefer _ = self.render_target_view.IUnknown.Release();

    try self.compileShaders();

    return self;
}

pub fn compileShaders(self: *D3D11Renderer) !void {
    var hresult = fxc.D3DCreateBlob(vertex_shader_source.len, @ptrCast(&self.vertex_shader_blob));
    try self.dxdi.DxgiCheckHresult(hresult);
    errdefer _ = self.vertex_shader_blob.IUnknown.Release();

    hresult = fxc.D3DCreateBlob(pixel_shader_source.len, @ptrCast(&self.pixel_shader_blob));

    try self.dxdi.DxgiCheckHresult(hresult);

    errdefer _ = self.pixel_shader_blob.IUnknown.Release();

    hresult = fxc.D3DCompile(
        pixel_shader_source,
        pixel_shader_source.len,
        null,
        null,
        null,
        "main",
        "ps_5_0",
        fxc.D3DCOMPILE_DEBUG,
        0,
        @ptrCast(&self.pixel_shader_blob),
        null,
    );

    try self.dxdi.DxgiCheckHresult(hresult);

    hresult = self.device.CreatePixelShader(
        @ptrCast(self.pixel_shader_blob.GetBufferPointer()),
        self.pixel_shader_blob.GetBufferSize(),
        null,
        &self.pixel_shader,
    );

    try self.dxdi.DxgiCheckHresult(hresult);

    errdefer _ = self.pixel_shader.IUnknown.Release();

    hresult = fxc.D3DCompile(
        vertex_shader_source,
        vertex_shader_source.len,
        null,
        null,
        null,
        "main",
        "vs_5_0",
        fxc.D3DCOMPILE_DEBUG,
        0,
        @ptrCast(&self.vertex_shader_blob),
        null,
    );

    try self.dxdi.DxgiCheckHresult(hresult);

    hresult = self.device.CreateVertexShader(
        @ptrCast(self.vertex_shader_blob.GetBufferPointer()),
        self.vertex_shader_blob.GetBufferSize(),
        null,
        &self.vertex_shader,
    );

    try self.dxdi.DxgiCheckHresult(hresult);

    // errdefer _ = self.vertex_shader.IUnknown.Release();
}

pub fn deinit(self: *D3D11Renderer) void {
    _ = self.swap_chain.IUnknown.Release();
    _ = self.context.IUnknown.Release();
    _ = self.device.IUnknown.Release();
    _ = self.render_target_view.IUnknown.Release();
    _ = self.vertex_shader.IUnknown.Release();
    _ = self.pixel_shader.IUnknown.Release();
    _ = self.vertex_shader_blob.IUnknown.Release();
    _ = self.pixel_shader_blob.IUnknown.Release();
}

pub fn renaderText(self: *D3D11Renderer, buffer: []const u8, x: u32, y: u32, color: ColorRGBA) void {
    _ = self;
    _ = buffer;
    _ = x;
    _ = y;
    _ = color;
}
pub fn clearBuffer(self: *D3D11Renderer, color: ColorRGBA) void {
    self.context.ClearRenderTargetView(self.render_target_view, &color.r);
}

pub fn presentBuffer(self: *D3D11Renderer) void {
    _ = self.swap_chain.Present(1, 0);
}

pub fn drawTestTriagnle(self: *D3D11Renderer) void {
    const vertices = [_]Vertex2D{
        .{ .x = 0, .y = 0.5 },
        .{ .x = 0.5, .y = -0.5 },
        .{ .x = -0.5, .y = -0.5 },
    };

    const stride: u32 = @sizeOf(Vertex2D);
    const offset: u32 = 0;

    const buffer_desc: d3d11.D3D11_BUFFER_DESC = .{
        .Usage = .DEFAULT,
        .BindFlags = .{ .VERTEX_BUFFER = 1 },
        .ByteWidth = @sizeOf(Vertex2D) * vertices.len,
        .StructureByteStride = @sizeOf(Vertex2D),
        .MiscFlags = .{},
        .CPUAccessFlags = .{},
    };

    const buffer_init_data: d3d11.D3D11_SUBRESOURCE_DATA = .{
        .pSysMem = &vertices,
        .SysMemPitch = 0,
        .SysMemSlicePitch = 0,
    };

    var vertex_buffer: *d3d11.ID3D11Buffer = undefined;
    var hresult = self.device.CreateBuffer(&buffer_desc, &buffer_init_data, &vertex_buffer);
    defer _ = vertex_buffer.IUnknown.Release();

    self.dxdi.DxgiCheckHresult(hresult) catch return;

    var input_layout: *d3d11.ID3D11InputLayout = undefined;
    const input_layout_descs = [_]d3d11.D3D11_INPUT_ELEMENT_DESC{
        .{
            .SemanticName = "Position",
            .SemanticIndex = 0,
            .Format = .R32G32_FLOAT,
            .InputSlot = 0,
            .AlignedByteOffset = 0,
            .InputSlotClass = .VERTEX_DATA,
            .InstanceDataStepRate = 0,
        },
    };

    hresult = self.device.CreateInputLayout(
        &input_layout_descs,
        input_layout_descs.len,
        @ptrCast(self.vertex_shader_blob.GetBufferPointer()),
        self.vertex_shader_blob.GetBufferSize(),
        &input_layout,
    );

    self.dxdi.DxgiCheckHresult(hresult) catch return;

    defer _ = input_layout.IUnknown.Release();

    const view_port: d3d11.D3D11_VIEWPORT = .{
        .Height = 400,
        .Width = 400,
        .MaxDepth = 1,
        .MinDepth = 0,
        .TopLeftX = 0,
        .TopLeftY = 0,
    };
    self.context.RSSetViewports(1, &view_port);

    self.context.IASetInputLayout(input_layout);

    self.context.PSSetShader(self.pixel_shader, null, 0);
    self.context.VSSetShader(self.vertex_shader, null, 0);

    self.context.OMSetRenderTargets(1, @ptrCast(&self.render_target_view), null);

    self.context.IASetVertexBuffers(
        0,
        1,
        @ptrCast(&vertex_buffer),
        @ptrCast(&stride),
        @ptrCast(&offset),
    );

    self.context.IASetPrimitiveTopology(._PRIMITIVE_TOPOLOGY_TRIANGLELIST);

    self.context.Draw(3, 0);
}

test "test triangle rendering" {
    const allocator = std.testing.allocator;

    var window: @import("../../window/root.zig").Window = .{
        .height = 400,
        .width = 400,
        .title = "test drawTexture",
    };

    try window.init(allocator);
    defer window.deinit();

    const renderer = &window.renderer;

    while (!window.exit) {
        window.pumpMessages();
        renderer.clearBuffer(ColorRGBA.Black);
        renderer.drawTestTriagnle();
        renderer.presentBuffer();
    }
}

test "test glyph rendering" {
    // const allocator = std.testing.allocator;
    //
    // var ft_library = try freetype.Library.init(allocator);
    // defer ft_library.deinit();
    //
    // const face = ft_library.face("C:\\windows\\Fonts\\arial.ttf", 32) catch |e| {
    //     std.log.err("freetype {}", .{e});
    //     return e;
    // };
    // defer face.deinit();
    //
    // const glyph = try face.getGlyph('a');
    // defer glyph.deinit();
}
