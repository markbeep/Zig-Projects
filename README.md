# Zig Projects ⚡️

To practice Zig I've started doing a varied selection of projects to foremost learn the language
and also see for myself how Zig handles different situations/projects. To avoid the clutter of
tons of small Zig projects filling my Github profile, each with an incomplete project, I've decided
to just create a general repo for all of these kinds of Zig projects.

While with these projects I do aim to make the code future proof and structure them like a long-term
project, I will most likely not continue or finish most of these projects. If there's any project
I find really nice I will make it its own repository.

## Projects 🦎

- **Tez:** Text Editor in Zig. Acronym actually came retrospectively. Just thought Tez would be funny
way to pun "text" with the typical 3 letter and Z words of Zig projects. Rewrote it in an attempt to
add Vim keybinds, but never got around to finishing the rewrite, so it is in a slightly broken state now.

- **Mez:** (Fullstack) messaging app. Main goal here was to try out how a web-server in Zig would work.
Frontend is slightly missing for it to be "fullstack" though. First project were I added a C library
(hiredis: C Redis library). Very powerful. Anybody can develop with or ontop of that project and hiredis
will automatically be downloaded and built by the Zig package manager making hiredis usable in the Zig
code without writing any wrappers.

- **TSX Parser:** This project uses two C libraries: tree-sitter and the Typescript/TSX tree-sitter plugin.
The motivation behind this project was to try out tree-sitter, get more experience with using a C library in
using C libraries in Zig, and also learning how the `extern` keyword can be used.
