# saphira_abi resolves symbols via dlsym(RTLD_DEFAULT), which needs a
# dynamic binary (static binaries carry no dynamic symbol table).
$(N).BINS:=$(B)/$(N).exe
