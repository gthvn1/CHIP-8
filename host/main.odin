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
Display_Proc :: proc(_: rawptr)

Game_API :: struct {
	lib:       dynlib.Library,
	path:      string,
	display:   Display_Proc,
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

	sym_display, sym_display_found := dynlib.symbol_address(lib, "display")
	if !sym_display_found {
		fmt.eprintln(dynlib.last_error())
		return
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

	fmt.printfln("The symbol %q was found at the address %v", "display", sym_display)
	fmt.printfln("The symbol %q was found at the address %v", "init", sym_init)
	fmt.printfln("The symbol %q was found at the address %v", "deinit", sym_deinit)
	fmt.printfln("The symbol %q was found at the address %v", "on_reload", sym_on_reload)

	ok = true
	api = {
		lib       = lib,
		path      = copy_path,
		display   = cast(Display_Proc)sym_display,
		init      = cast(Init_Proc)sym_init,
		deinit    = cast(Deinit_Proc)sym_deinit,
		on_reload = cast(OnReload_Proc)sym_on_reload,
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

main_loop :: proc(path: string) {
	last_modification, modif_err := os.modification_time_by_path(path)
	if modif_err != nil {
		fmt.eprintfln(
			"Failed to get modification date for %s: %s",
			path,
			os.error_string(modif_err),
		)
		return
	}

	version := 1
	game, game_loaded := load_game(path, version)
	if !game_loaded {return}

	state_ptr := game.init()
	if state_ptr == nil {unload_game(game); return}

	fmt.printfln("Got ptr %p", state_ptr)
	// Currently we cannot escape the loop so defer is never called. But we will have
	// a clean end one day...
	defer game.deinit(state_ptr)

	rl.InitWindow(800, 600, "CHIP-8 Emulator")
	defer rl.CloseWindow()

	// Invariant: game always contains the last library successfully loaded.
	for !rl.WindowShouldClose() {
		t := os.modification_time_by_path(path) or_continue
		if t != last_modification {
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
			// retry on the next compilation.
			last_modification = t

			// Load a new version of the library
			version += 1
			new_game, new_game_loaded := load_game(path, version)
			if !new_game_loaded {
				fmt.eprintln("failed to load the new library, keep the old one")
				continue
			}

			// Before unloaded game we need to check if the rawptr has changed...
			new_state_ptr := new_game.on_reload(state_ptr)
			if new_state_ptr == nil {
				fmt.eprintln("Something weird happens with the new state, keep the old one")
				unload_game(new_game)
				continue
			}

			if new_state_ptr != state_ptr {
				fmt.eprintln("Cleanup old state, a new one has been initialized")
				game.deinit(state_ptr)
				state_ptr = new_state_ptr
			}

			// The new library is successfully loaded, state is updated so we can unload the old one
			unload_game(game)

			// Even if unload failed we have the new one that is successfully loaded so use it
			game = new_game
		}

		rl.BeginDrawing()
		game.display(state_ptr)
		rl.EndDrawing()
	}
}

main :: proc() {
	main_loop("./temp/game.so")
}
