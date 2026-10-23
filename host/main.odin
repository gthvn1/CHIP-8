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
On_Reload_Proc :: proc(_: rawptr) -> rawptr
Update_Proc :: proc(_: rawptr)
Render_Proc :: proc(_: rawptr)

Emulator_State :: struct {
	mtime:   time.Time,
	ptr:     rawptr,
	api:     Emulator_API,
	version: int,
}

Emulator_API :: struct {
	lib:       dynlib.Library,
	path:      string,
	init:      Init_Proc,
	deinit:    Deinit_Proc,
	on_reload: On_Reload_Proc,
	update:    Update_Proc,
	render:    Render_Proc,
}

load_emulator :: proc(lib_path: string, version: int) -> (api: Emulator_API, ok: bool) {
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

	// We keep copy_path to be able to have symbols in gdb.
	// If the file is removed the code will work but symbols won't be available in gdb.
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

	sym_update, sym_update_found := dynlib.symbol_address(lib, "update")
	if !sym_update_found {
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
	fmt.printfln("The symbol %q was found at the address %v", "update", sym_update)
	fmt.printfln("The symbol %q was found at the address %v", "render", sym_render)

	ok = true
	api = {
		lib       = lib,
		path      = copy_path,
		init      = cast(Init_Proc)sym_init,
		deinit    = cast(Deinit_Proc)sym_deinit,
		on_reload = cast(On_Reload_Proc)sym_on_reload,
		update    = cast(Update_Proc)sym_update,
		render    = cast(Render_Proc)sym_render,
	}
	return
}

unload_emulator :: proc(emu: Emulator_API) {
	if !dynlib.unload_library(emu.lib) {
		fmt.eprintln(dynlib.last_error())
	}

	if err := os.remove(emu.path); err != nil {
		fmt.eprintfln("Failed to remove %s: %s", emu.path, os.error_string(err))
	}

	delete(emu.path)
}

init_emulator_state :: proc(path: string) -> (state: Emulator_State, ok: bool) {
	mtime, err := os.modification_time_by_path(path)
	if err != nil {
		fmt.eprintfln("Failed to get modification date for %s: %s", path, os.error_string(err))
		return
	}

	emu, emu_loaded := load_emulator(path, 1)
	if !emu_loaded {
		fmt.eprintln("Failed to load CHIP-8")
		return
	}

	state_ptr := emu.init()
	if state_ptr == nil {
		fmt.eprintln("Failed to get CHIP-8 state")
		unload_emulator(emu)
		return
	}

	ok = true
	state = Emulator_State {
		mtime   = mtime,
		api     = emu,
		ptr     = state_ptr,
		version = 1,
	}

	return
}

hot_reload :: proc(emu: ^Emulator_State, path: string) {
	t, err := os.modification_time_by_path(path)
	if err != nil {
		fmt.eprintln(os.error_string(err))
		return
	}

	if t == emu.mtime {return}

	// NOTE
	// A new version of the library is available. We try to load the new version before
	// unloading the old one for two reasons.
	// - The first reason is that if the load fails we keep the old version
	// - The second is because raylib is a dependency of our chip8.so. Raylib is unloaded
	//   only when no loaded copy of chip8.so needs it anymore.
	//   By loading the new chip8.so first we ensure that raylib is always used and loaded.
	//   Of course it means that raylib is not statically linked but dynamically linked.
	//   Updated: as we are now using raylib from host the second point is not true because
	//            it is always used but keep the remark as a reminder.
	fmt.printfln("A new version of %s is available", path)

	// In any case we update the last modification. If it fails we will
	// retry on the next compilation and it prevents to loop on build failure.
	emu.mtime = t

	// Load a new version of the library
	version := emu.version + 1
	new_emu, new_emu_loaded := load_emulator(path, version)
	if !new_emu_loaded {
		fmt.eprintln("failed to load the new library, keep the old one")
		return
	}

	// Before unloading the old emulator we need to check if the rawptr has changed...
	new_ptr := new_emu.on_reload(emu.ptr)
	if new_ptr == nil {
		fmt.eprintln("Keeping old emulator")
		unload_emulator(new_emu)
		return
	}

	if new_ptr != emu.ptr {
		fmt.eprintln("Cleanup old state, a new one has been initialized")
		emu.api.deinit(emu.ptr)
	}

	// The new library is successfully loaded, state is updated so we can unload the old one
	unload_emulator(emu.api)

	// Even if unload failed we have the new one that is successfully loaded so use it.
	// "mtime" is already correct here.
	emu.version = version
	emu.api = new_emu
	emu.ptr = new_ptr
}

main_loop :: proc(path: string) -> bool {
	// Emulator expects an initialized window. So start by initializing the raylib window.
	rl.InitWindow(800, 600, "CHIP-8 Emulator")
	defer rl.CloseWindow()

	// init emulator will load the chip8.so. So we need to defer the unload now because
	// defer are executed in reverse order.
	emu, ok := init_emulator_state(path)
	if !ok {
		return false
	}
	defer unload_emulator(emu.api)

	fmt.printfln("Got ptr %p", emu.ptr)
	// Our invariant is that emulator is always the last library so emu.deinit will
	// be called with a successfully loaded emulator.
	defer emu.api.deinit(emu.ptr)

	// Set our loop to run at 60 frames per second
	rl.SetTargetFPS(60)

	// Invariant: emu always contains the last library successfully loaded.
	for !rl.WindowShouldClose() {
		hot_reload(&emu, path)

		emu.api.update(emu.ptr)

		rl.BeginDrawing()
		emu.api.render(emu.ptr)
		rl.EndDrawing()
	}

	return true
}

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintfln("usage: %s library", os.args[0])
		fmt.eprintln("  library: path of the shared library to hot reload (e.g. ./temp/chip8.so)")
		os.exit(1)
	}
	if !main_loop(os.args[1]) {
		os.exit(1)
	}
}
