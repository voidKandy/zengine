const rl = @import("raylib");

pub const ScreenPosition =
    struct {
        x: i32,
        y: i32,
    };
/// position of the image to be rendered on the screen
position: ScreenPosition,
image: rl.Image,

/// For now, the image is always drawn with a raywhite color
pub fn draw(self: @This()) rl.RaylibError!void {
    const texture = try self.image.toTexture();
    rl.drawTexture(texture, self.position.x, self.position.y, rl.Color.ray_white);
}
