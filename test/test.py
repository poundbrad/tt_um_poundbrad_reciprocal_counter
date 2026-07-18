# SPDX-FileCopyrightText: © 2026 Brad Pound
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_project(dut):
    """Verify the temporary Tiny Tapeout placeholder wrapper."""

    dut._log.info("Starting placeholder wrapper test")

    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    # Initial input values
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    # Apply reset
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

    # The temporary wrapper must drive all outputs low.
    test_inputs = [
        (0x00, 0x00),
        (0x14, 0x1E),
        (0x55, 0xAA),
        (0xFF, 0xFF),
    ]

    for ui_value, uio_value in test_inputs:
        dut.ui_in.value = ui_value
        dut.uio_in.value = uio_value

        await ClockCycles(dut.clk, 1)

        expected = (ui_value + uio_value) & 0xFF

        assert int(dut.uo_out.value) == expected, (
            f"uo_out was {dut.uo_out.value}, expected {expected}"
        )
        assert int(dut.uio_out.value) == 0
        assert int(dut.uio_oe.value) == 0

    dut._log.info("Placeholder wrapper test passed")
