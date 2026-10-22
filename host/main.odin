package host

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:time"

Host_Error :: enum {
	None,
	Load_Failed,
	Unload_Failed,
	Symbol_Not_Found,
}

Error :: union #shared_nil {
	Host_Error,
	os.Error,
}

Display_Proc :: proc()

Game_API :: struct {
	lib:     dynlib.Library,
	display: Display_Proc,
}

load_game :: proc(lib_path: string) -> (api: Game_API, err: Error) {
	lib, lib_loaded := dynlib.load_library(lib_path)
	if !lib_loaded {
		fmt.eprintln(dynlib.last_error())
		err = .Load_Failed
		return
	}

	sym, sym_found := dynlib.symbol_address(lib, "display")
	if !sym_found {
		fmt.eprintln(dynlib.last_error())
		dynlib.unload_library(lib)
		err = .Symbol_Not_Found
		return
	}

	fmt.printfln("The symbol %q was found at the address %v", "display", sym)

	api = {
		lib     = lib,
		display = cast(Display_Proc)sym,
	}
	return
}

unload_lib :: proc(l: dynlib.Library) -> Error {
	if !dynlib.unload_library(l) {
		fmt.eprintln(dynlib.last_error())
		return .Unload_Failed
	}

	return nil
}

run_forever :: proc(path: string) -> Error {
	last_modification := os.modification_time_by_path(path) or_return
	game := load_game(path) or_return

	for {
		game.display()
		time.sleep(1 * time.Second)
		t := os.modification_time_by_path(path) or_continue
		if t != last_modification {
			fmt.printfln("%s has been modified", path)
			unload_lib(game.lib) or_return
			game = load_game(path) or_return
			last_modification = t
		}
	}
}

main :: proc() {
	switch e in run_forever("./temp/game.so") {
	case Host_Error:
		switch e {
		case .None:
			fmt.eprintln("None is not expected")
		case .Load_Failed:
			fmt.eprintln("Load Failed")
		case .Unload_Failed:
			fmt.eprintln("Unload Failed")
		case .Symbol_Not_Found:
			fmt.eprintln("Symbol not found")
		}
	case os.Error:
		fmt.eprintln(os.error_string(e))
	}

	os.exit(1)
}
