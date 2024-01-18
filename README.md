# Tez ⚡️

### Lightweight text editor written in Zig

Tez is a side project to learn Zig better while also making a lightweight and usable editor.

![Hello world example in zig using Tez](media/hello_world.png)

## Usage

Tez currently has a very limited functionality. For now, you can only open and edit already existing files:

```sh
tez sample.txt
```

It cannot create new files right now. If you give a non-existing file as the argument, tez will crash.

You can also just open the editor by using `tez` on its own. Currently pressing `q` will close the program
so there's no way to even type the letter Q. In the future control keys or a mode-system like in vim will be
added.

## Local Development

Project was built using [Zig v0.12.0](https://github.com/ziglang/zig). For local development execute:

```sh
zig build run
```

### Nix

Alternatively you can also use Nix:

```sh
nix develop github:markbeep/Tez # get required development tools
nix run github:markbeep/Tez # directly runs the editor
```

_Note, leave out the `github:markbeep/Tez` when you want to run the local version._
