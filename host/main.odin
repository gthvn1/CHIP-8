package host

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:time"

// dynamically linked, vendor:raylib uses system:raylib
// See $(odin root)/vendor/raylib/raylib.odin:102
import rl "vendor:raylib"

Init_Proc :: proc() -> rawptr
Deinit_Proc :: proc(_: rawptr)
OnReload_Proc :: proc(_: rawptr) -> rawptr
Render_Proc :: proc(_: rawptr)

Game_State :: struct {
	build:   time.Time,
	ptr:     rawptr,
	api:     Game_API,
	version: int,
}

Game_API :: struct {
	lib:       dynlib.Library,
	path:      string,
	render:    Render_Proc,
	init:      Init_Proc,
	deinit:    Deinit_Proc,
	on_reload: OnReload_Proc,
}

load_game :: proc(lib_path: string, version: int) -> (api: Game_API, ok: bool) {
	// man dlopen: If the same shared object is opened again with dlopen(),
	// the same object handle is returned. That is why we are using a unique
	// name.
	now := time.now()
	year, month, day := time.date(now)
	hour, min, sec := time.clock(now)
	copy_path := fmt.aprintf(
		"%s-%04d%02d%02d-%02d%02d%02d-%d",
		lib_path,
		year,
		int(month),
		day,
		hour,
		min,
		sec,
		version,
	)

	// We keep copy_path in Game to be able to have symbols in gdb.
	// If the file is removed the code will work but symbols won't be available
	// in gdb.
	defer if !ok {
		delete(copy_path)
	}

	if err := os.copy_file(copy_path, lib_path); err != nil {
		fmt.eprintfln("Failed to copy %s to %s: %s", lib_path, copy_path, os.error_string(err))
		return
	}

	defer if !ok {
		if err := os.remove(copy_path); err != nil {
			fmt.eprintfln("Failed to remove %s: %s", copy_path, os.error_string(err))
		}
	}

	lib, lib_loaded := dynlib.load_library(copy_path)
	if !lib_loaded {
		fmt.eprintln(dynlib.last_error())
		return
	}

	defer if !ok {
		dynlib.unload_library(lib)
	}

	sym_init, sym_init_found := dynlib.symbol_address(lib, "init")
	if !sym_init_found {
		fmt.eprintln(dynlib.last_error())
		return
	}

	sym_deinit, sym_deinit_found := dynlib.symbol_address(lib, "deinit")
	if !sym_deinit_found {
		fmt.eprintln(dynlib.last_error())
		return
	}

	sym_on_reload, sym_on_reload_found := dynlib.symbol_address(lib, "on_reload")
	if !sym_on_reload_found {
		fmt.eprintln(dynlib.last_error())
		return
	}

	sym_render, sym_render_found := dynlib.symbol_address(lib, "render")
	if !sym_render_found {
		fmt.eprintln(dynlib.last_error())
		return
	}

	fmt.printfln("The symbol %q was found at the address %v", "init", sym_init)
	fmt.printfln("The symbol %q was found at the address %v", "deinit", sym_deinit)
	fmt.printfln("The symbol %q was found at the address %v", "on_reload", sym_on_reload)
	fmt.printfln("The symbol %q was found at the address %v", "render", sym_render)

	ok = true
	api = {
		lib       = lib,
		path      = copy_path,
		init      = cast(Init_Proc)sym_init,
		deinit    = cast(Deinit_Proc)sym_deinit,
		on_reload = cast(OnReload_Proc)sym_on_reload,
		render    = cast(Render_Proc)sym_render,
	}
	return
}

unload_game :: proc(game: Game_API) {
	if !dynlib.unload_library(game.lib) {
		fmt.eprintln(dynlib.last_error())
	}

	if err := os.remove(game.path); err != nil {
		fmt.eprintfln("Failed to remove %s: %s", game.path, os.error_string(err))
	}

	delete(game.path)
}

init_game_state :: proc(path: string) -> (state: Game_State, ok: bool) {
	last_build, err := os.modification_time_by_path(path)
	if err != nil {
		fmt.eprintfln("Failed to get modification date for %s: %s", path, os.error_string(err))
		return
	}

	game, game_ok := load_game(path, 1)
	if !game_ok {
		fmt.eprintln("Failed to load game")
		return
	}

	state_ptr := game.init()
	if state_ptr == nil {
		fmt.eprintln("Failed to get state")
		unload_game(game)
		return
	}

	ok = true
	state = Game_State {
		build   = last_build,
		api     = game,
		ptr     = state_ptr,
		version = 1,
	}

	return
}

main_loop :: proc(path: string) -> bool {
	// Game expects a initialized window. So start by initializing the raylib window.
	rl.InitWindow(800, 600, "CHIP-8 Emulator")
	defer rl.CloseWindow()

	// init game will load the game.so. So we need to defer the unload now because
	// defer are executed in reverse order.
	game_state, ok := init_game_state(path)
	if !ok {
		return false
	}
	defer unload_game(game_state.api)

	fmt.printfln("Got ptr %p", game_state.ptr)
	// Our invariant is that game is always that last library so game.deinit will
	// be called with a successfully loaded game.
	defer game_state.api.deinit(game_state.ptr)

	// Set our loop to run at 60 frames per second
	rl.SetTargetFPS(60)

	// Invariant: game always contains the last library successfully loaded.
	for !rl.WindowShouldClose() {
		t := os.modification_time_by_path(path) or_continue
		if t != game_state.build {
			// NOTE
			// A new version of the library is available. We try to load the new version before
			// unloading the old one for two reasons.
			// - The first reason is that if the load fails we keep the old version
			// - The second is because raylib is a dependency of our game.so. Raylib is unloaded
			//   only when no loaded copy of game.so needs it anymore.
			//   By loading the new game.so first we ensure that raylib is always used and loaded.
			//   Of course it means that raylib is not statically linked but dynamically linked.
			//   Updated: as we are now using raylib from host the second point is not true because
			//            it is always use but keep the remark as a remainder.
			fmt.printfln("A new version of %s is available", path)

			// In any case we update the last modification. If it fails we will
			// retry on the next compilation and it prevents to loop on failure build.
			game_state.build = t

			// Load a new version of the library
			version := game_state.version + 1
			new_game, new_game_loaded := load_game(path, version)
			if !new_game_loaded {
				fmt.eprintln("failed to load the new library, keep the old one")
				continue
			}

			// Before unloaded game we need to check if the rawptr has changed...
			new_ptr := new_game.on_reload(game_state.ptr)
			if new_ptr == nil {
				fmt.eprintln("Something weird happens with the new state, keep the old one")
				unload_game(new_game)
				continue
			}

			if new_ptr != game_state.ptr {
				fmt.eprintln("Cleanup old state, a new one has been initialized")
				game_state.api.deinit(game_state.ptr)
			}

			// The new library is successfully loaded, state is updated so we can unload the old one
			unload_game(game_state.api)

			// Even if unload failed we have the new one that is successfully loaded so use it.
			// host_state.build is already correct here.
			game_state.version = version
			game_state.api = new_game
			game_state.ptr = new_ptr
		}

		rl.BeginDrawing()
		game_state.api.render(game_state.ptr)
		rl.EndDrawing()
	}

	return true
}

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintfln("usage: %s library", os.args[0])
		fmt.eprintln("  library: path of the shared library to hot reload (e.g. ./temp/game.so)")
		os.exit(1)
	}
	if !main_loop(os.args[1]) {
		os.exit(1)
	}
}
