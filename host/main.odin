package host

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:time"

Display_Proc :: proc()

Game_API :: struct {
	lib:     dynlib.Library,
	path:    string,
	display: Display_Proc,
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

	sym, sym_found := dynlib.symbol_address(lib, "display")
	if !sym_found {
		fmt.eprintln(dynlib.last_error())
		return
	}

	fmt.printfln("The symbol %q was found at the address %v", "display", sym)
	ok = true
	api = {
		lib     = lib,
		path    = copy_path,
		display = cast(Display_Proc)sym,
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

run_forever :: proc(path: string) {
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

	// Invariant: game always contains the last library successfully loaded.
	for {
		game.display()
		time.sleep(1 * time.Second)
		t := os.modification_time_by_path(path) or_continue
		if t != last_modification {
			fmt.printfln("%s has been modified", path)
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

			// The new library is successfully loaded so we can unload the old one
			unload_game(game)

			// Even if unload failed we have the new one that is successfully loaded so use it
			game = new_game
		}
	}
}

main :: proc() {
	run_forever("./temp/game.so")
	os.exit(1)
}
