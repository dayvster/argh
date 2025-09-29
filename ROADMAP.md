# Roadmap for argh

This document tracks planned and potential features for future releases of argh. Contributions and suggestions are welcome!


## Roadmap

- [x] Type-safe option parsing (int, float, min/max)
- [x] Argument count constraints (min/max for positionals)
- [x] Better help formatting (grouping, wrapping, usage examples)
- [x] Configurable help output style (flat/simple/complex grouping)
- [x] Grouped help output (simple_grouped, complex_grouped placeholder)
- [x] Short options for all option types (e.g. -n, -c, -L)
- [x] Type-safe bool option access (getOptionBool)
- [x] Memory safety (no leaks, all allocations freed)
- [x] Full API doc comments
- [ ] Environment variable fallback for options
- [ ] Subcommand support (e.g. `git commit`)
- [ ] Argument deprecation warnings
- [ ] Config file support (e.g. JSON, TOML)
- [ ] Hidden arguments (not shown in help)
- [ ] Custom validators for arguments
- [ ] Shell completion script generation (bash, zsh, fish)
- [ ] Argument aliases (multiple names for the same flag/option)
- [ ] More advanced mutually exclusive/required group logic

---


---

Recent progress:
- Grouped help output and short options are now supported.
- Type-safe bool option access (getOptionBool) is available.
- Memory safety improvements: all allocations are freed, no leaks.

Feel free to open an issue or PR to discuss or help implement any of these features!
