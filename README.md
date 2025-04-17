## Unnamed Engine Project
I am building a game engine using `raylib` for rendering and `bullet` for physics simulation.

### Info on the build script
Everything in `bins` **MUST** have a `public` `main` function.
Each can be run by running `zig build <name-of-binary>`. For example, to run the `bins/entity.zig` you would run `zig build entity`.
If you would like to run tests across all the binaries simply run `zig build test`. 
