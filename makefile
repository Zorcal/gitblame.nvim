.PHONE: test
test:
	# Requires https://github.com/nvim-lua/plenary.nvim to be checkout out in
	# the parent directory of this repository.
	nvim --headless --noplugin -u tests/minimal.vim -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal.vim'}"
