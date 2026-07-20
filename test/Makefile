SIM ?= icarus

TOPLEVEL_LANG = verilog

# This Makefile lives in <Tiny Tapeout repository>/test.
PROJECT_ROOT := $(abspath ..)

VERILOG_SOURCES = \
    $(PROJECT_ROOT)/test/tb.v \
    $(PROJECT_ROOT)/src/tt_um_poundbrad_reciprocal_counter.v \
    $(PROJECT_ROOT)/src/reciprocal_counter.v \
    $(PROJECT_ROOT)/src/reciprocal_channel.v \
    $(PROJECT_ROOT)/src/spi_register_interface.v \
    $(PROJECT_ROOT)/src/register_file.v

COMPILE_ARGS += -g2012

TOPLEVEL = tb
MODULE = test_reciprocal_counter

include $(shell cocotb-config --makefiles)/Makefile.sim
