# CHIP-8 emulator in Odin

Implement a [CHIP-8] emulator in [Odin], developed with hot reloading.

We start with an emulator that does nothing, then implement the
opcodes one by one. The fun part: we see the progress live while
coding! A nice project to learn [Odin]!!!

- To build everything: `./build.sh all`
- Once built, you can start the host in a terminal: `./temp/host`
- And in another terminal modify the code in `game/`, rebuild it with
  `./build.sh game` and you should see the change live
- For a full live experience you can run in a terminal: `ls game/*.odin | entr -c ./build.sh game`.

[CHIP-8]: https://chip-8.github.io/links/
[Odin]: https://odin-lang.org/
