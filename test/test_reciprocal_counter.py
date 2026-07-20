# SPDX-FileCopyrightText: © 2026 Brad Pound
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer


# ---------------------------------------------------------------------------
# Simulation constants
# ---------------------------------------------------------------------------

# Project Genesis reference clock is approximately 7.2 MHz.
#
# 1 / 7.2 MHz = 138.889 ns
#
# An integer 139 ns period is used for simulation.
REF_CLK_PERIOD_NS = 139

# Conservative SPI mode-0 clock:
#
# half period = 2000 ns
# full period = 4000 ns
# SPI frequency = 250 kHz
#
# The standalone SPI test already verifies operation at 500 kHz.
SPI_HALF_PERIOD_NS = 2000

# Allow a small measurement difference due to input synchronization and
# reference-clock boundary alignment.
COUNT_TOLERANCE = 3


# ---------------------------------------------------------------------------
# SPI protocol
# ---------------------------------------------------------------------------

CMD_WRITE = 0x00
CMD_READ = 0x01


# ---------------------------------------------------------------------------
# Register map
# ---------------------------------------------------------------------------

ADDR_CH0_GATE_CYCLES = 0x00
ADDR_CH1_GATE_CYCLES = 0x04

ADDR_CH0_TIMEOUT_REFCOUNT = 0x08
ADDR_CH1_TIMEOUT_REFCOUNT = 0x0C

ADDR_CH0_COUNT = 0x10
ADDR_CH1_COUNT = 0x14

ADDR_CH0_MEASUREMENT_COUNT = 0x18
ADDR_CH1_MEASUREMENT_COUNT = 0x1C


# ---------------------------------------------------------------------------
# Generic conversion helpers
# ---------------------------------------------------------------------------

def bytes_to_bits(values):
    """Convert a list of bytes into an MSB-first list of bits."""

    bits = []

    for value in values:
        for bit_index in range(7, -1, -1):
            bits.append((value >> bit_index) & 1)

    return bits


def bits_to_integer(bits):
    """Convert an MSB-first list of bits into one integer."""

    value = 0

    for bit in bits:
        value = (value << 1) | int(bit)

    return value


def make_write_frame(address, data):
    """Create one complete 48-bit SPI register-write frame."""

    return [
        CMD_WRITE,
        address & 0xFF,
        (data >> 24) & 0xFF,
        (data >> 16) & 0xFF,
        (data >> 8) & 0xFF,
        data & 0xFF,
    ]


def make_read_frame(address):
    """Create one complete 48-bit SPI register-read frame."""

    return [
        CMD_READ,
        address & 0xFF,
        0x00,
        0x00,
        0x00,
        0x00,
    ]


# ---------------------------------------------------------------------------
# DUT initialization and reset
# ---------------------------------------------------------------------------

async def reset_dut(dut):
    """Initialize the Tiny Tapeout wrapper inputs and reset the design."""

    # Tiny Tapeout infrastructure inputs.
    dut.ena.value = 1
    dut.uio_in.value = 0

    # SPI mode-0 idle state. These scalar testbench signals are connected
    # to ui_in[2], ui_in[3], and ui_in[4].
    dut.spi_sclk.value = 0
    dut.spi_mosi.value = 0
    dut.spi_cs_n.value = 1

    # Sensor-frequency inputs connect to ui_in[0] and ui_in[1].
    dut.ch0_signal_in.value = 0
    dut.ch1_signal_in.value = 0

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)

    dut.rst_n.value = 1

    # Allow reset release and the SPI synchronizers to settle.
    await ClockCycles(dut.clk, 8)

    # Verify the wrapper's unused outputs and bidirectional enables.
    assert (int(dut.uo_out.value) & 0xFE) == 0, (
        "Unused dedicated outputs uo_out[7:1] are not low"
    )
    assert int(dut.uio_out.value) == 0, (
        "Unused bidirectional output values are not low"
    )
    assert int(dut.uio_oe.value) == 0, (
        "Unused bidirectional pins are not disabled"
    )


async def start_reference_clock(dut):
    """Start the approximately 7.2 MHz system reference clock."""

    clock = Clock(
        dut.clk,
        REF_CLK_PERIOD_NS,
        units="ns",
    )

    cocotb.start_soon(clock.start())


# ---------------------------------------------------------------------------
# SPI helpers
# ---------------------------------------------------------------------------

async def spi_transfer_bits(
    dut,
    tx_bits,
    half_period_ns=SPI_HALF_PERIOD_NS,
):
    """
    Transfer an arbitrary number of SPI mode-0 bits.

    Mode 0 behavior:

        CPOL = 0
        CPHA = 0

        MOSI is changed while SCLK is low.
        MOSI is sampled by the DUT on rising SCLK edges.
        MISO is sampled by the testbench while SCLK is high.
        The DUT advances MISO on falling SCLK edges.

    Bits are sent MSB first.
    """

    rx_bits = []

    # Begin in the inactive state.
    dut.spi_sclk.value = 0
    dut.spi_mosi.value = 0
    dut.spi_cs_n.value = 1

    await ClockCycles(dut.clk, 4)

    # Select the SPI slave and allow CS_n to pass through its synchronizer.
    dut.spi_cs_n.value = 0
    await ClockCycles(dut.clk, 4)

    for tx_bit in tx_bits:
        # Present MOSI while SCLK is low.
        dut.spi_mosi.value = tx_bit
        await Timer(half_period_ns, units="ns")

        # Rising edge: DUT samples MOSI.
        dut.spi_sclk.value = 1
        await Timer(half_period_ns, units="ns")

        # Sample MISO near the end of the SCLK-high interval.
        rx_bits.append(int(dut.spi_miso.value))

        # Falling edge: DUT prepares the next MISO bit.
        dut.spi_sclk.value = 0

    # Allow the final falling edge to pass through the synchronizer.
    await Timer(half_period_ns, units="ns")

    # Release the SPI slave.
    dut.spi_cs_n.value = 1
    dut.spi_mosi.value = 0

    # Allow synchronized CS_n to reset the SPI frame state.
    await ClockCycles(dut.clk, 5)

    assert int(dut.spi_miso.value) == 0, (
        "MISO did not return low after CS_n was released"
    )

    return rx_bits


async def spi_transfer_frame(
    dut,
    tx_bytes,
    half_period_ns=SPI_HALF_PERIOD_NS,
):
    """Transfer one complete byte-oriented SPI frame."""

    return await spi_transfer_bits(
        dut,
        bytes_to_bits(tx_bytes),
        half_period_ns,
    )


async def spi_write_register(dut, address, value):
    """Write one 32-bit value through the complete SPI interface."""

    await spi_transfer_frame(
        dut,
        make_write_frame(address, value),
    )


async def spi_read_register(dut, address):
    """Read one 32-bit register through the complete SPI interface."""

    rx_bits = await spi_transfer_frame(
        dut,
        make_read_frame(address),
    )

    # Bits 0-7:
    #   command transfer
    #
    # Bits 8-15:
    #   address transfer
    #
    # Bits 16-47:
    #   32-bit register data returned on MISO
    return bits_to_integer(rx_bits[16:48])


async def configure_channel(
    dut,
    channel,
    gate_cycles,
    timeout_refcount,
):
    """
    Configure one reciprocal channel through SPI.

    The timeout is written before gate_cycles. Since gate_cycles == 0
    disables the channel, this ensures the channel is fully configured
    before it is enabled.
    """

    if channel == 0:
        gate_address = ADDR_CH0_GATE_CYCLES
        timeout_address = ADDR_CH0_TIMEOUT_REFCOUNT
    elif channel == 1:
        gate_address = ADDR_CH1_GATE_CYCLES
        timeout_address = ADDR_CH1_TIMEOUT_REFCOUNT
    else:
        raise ValueError(f"Unsupported channel: {channel}")

    await spi_write_register(
        dut,
        timeout_address,
        timeout_refcount,
    )

    await spi_write_register(
        dut,
        gate_address,
        gate_cycles,
    )


# ---------------------------------------------------------------------------
# Sensor-frequency stimulus
# ---------------------------------------------------------------------------

async def drive_square_wave(
    signal,
    period_ns,
    start_delay_ns,
):
    """
    Continuously drive an asynchronous square-wave input.

    The start delay prevents sensor edges from being deliberately aligned
    with reference-clock edges.
    """

    if period_ns <= 0:
        raise ValueError("period_ns must be positive")

    if period_ns % 2 != 0:
        raise ValueError("period_ns must be an even integer")

    half_period_ns = period_ns // 2

    signal.value = 0
    await Timer(start_delay_ns, units="ns")

    while True:
        signal.value = 1
        await Timer(half_period_ns, units="ns")

        signal.value = 0
        await Timer(half_period_ns, units="ns")


async def wait_for_measurement(
    dut,
    measurement_count_address,
    maximum_polls=10,
):
    """
    Poll a channel's completed-measurement counter through SPI.

    Each SPI read takes substantially longer than the small reciprocal
    measurements used in this test, so a measurement will normally be
    detected on the first poll.
    """

    for _ in range(maximum_polls):
        measurement_count = await spi_read_register(
            dut,
            measurement_count_address,
        )

        if measurement_count > 0:
            return measurement_count

        await ClockCycles(dut.clk, 20)

    raise AssertionError(
        f"No completed measurement after {maximum_polls} SPI polls"
    )


def assert_count_close(actual, expected, channel_name):
    """Check the reciprocal result with synchronization tolerance."""

    difference = abs(actual - expected)

    assert difference <= COUNT_TOLERANCE, (
        f"{channel_name} measured {actual} reference clocks; "
        f"expected approximately {expected}; "
        f"difference={difference}"
    )


# ---------------------------------------------------------------------------
# Test 1: SPI-to-register-file connections
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_spi_configuration_register_connections(dut):
    """
    Verify SPI writes and reads for both channels' configuration registers.

    This checks:

        SPI input pins
        SPI command decoding
        SPI address decoding
        SPI write-data shifting
        internal register bus
        register-file storage
        register-file read mux
        SPI read-data shifting
        MISO output
    """

    await start_reference_clock(dut)
    await reset_dut(dut)

    dut._log.info("Checking reset values through SPI")

    assert await spi_read_register(
        dut,
        ADDR_CH0_GATE_CYCLES,
    ) == 0

    assert await spi_read_register(
        dut,
        ADDR_CH1_GATE_CYCLES,
    ) == 0

    assert await spi_read_register(
        dut,
        ADDR_CH0_TIMEOUT_REFCOUNT,
    ) == 0

    assert await spi_read_register(
        dut,
        ADDR_CH1_TIMEOUT_REFCOUNT,
    ) == 0

    dut._log.info("Writing different CH0 and CH1 configuration values")

    await configure_channel(
        dut,
        channel=0,
        gate_cycles=4,
        timeout_refcount=1000,
    )

    await configure_channel(
        dut,
        channel=1,
        gate_cycles=7,
        timeout_refcount=2000,
    )

    assert await spi_read_register(
        dut,
        ADDR_CH0_GATE_CYCLES,
    ) == 4

    assert await spi_read_register(
        dut,
        ADDR_CH1_GATE_CYCLES,
    ) == 7

    assert await spi_read_register(
        dut,
        ADDR_CH0_TIMEOUT_REFCOUNT,
    ) == 1000

    assert await spi_read_register(
        dut,
        ADDR_CH1_TIMEOUT_REFCOUNT,
    ) == 2000

    # No sensor signals were driven.
    assert await spi_read_register(
        dut,
        ADDR_CH0_MEASUREMENT_COUNT,
    ) == 0

    assert await spi_read_register(
        dut,
        ADDR_CH1_MEASUREMENT_COUNT,
    ) == 0


# ---------------------------------------------------------------------------
# Test 2: Channel 0 end-to-end
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_ch0_spi_end_to_end(dut):
    """
    Configure CH0 through SPI, drive CH0, and read its result through SPI.

    CH1 remains disabled.
    """

    await start_reference_clock(dut)
    await reset_dut(dut)

    gate_cycles = 4

    # Exactly 40 simulated reference-clock periods.
    signal_period_ref_clocks = 40
    signal_period_ns = (
        signal_period_ref_clocks
        * REF_CLK_PERIOD_NS
    )

    expected_count = (
        gate_cycles
        * signal_period_ref_clocks
    )

    await configure_channel(
        dut,
        channel=0,
        gate_cycles=gate_cycles,
        timeout_refcount=10_000,
    )

    assert await spi_read_register(
        dut,
        ADDR_CH1_GATE_CYCLES,
    ) == 0

    signal_task = cocotb.start_soon(
        drive_square_wave(
            dut.ch0_signal_in,
            period_ns=signal_period_ns,
            start_delay_ns=311,
        )
    )

    completed = await wait_for_measurement(
        dut,
        ADDR_CH0_MEASUREMENT_COUNT,
    )

    measured_count = await spi_read_register(
        dut,
        ADDR_CH0_COUNT,
    )

    ch1_count = await spi_read_register(
        dut,
        ADDR_CH1_COUNT,
    )

    ch1_completed = await spi_read_register(
        dut,
        ADDR_CH1_MEASUREMENT_COUNT,
    )

    dut._log.info(
        "CH0 count=%d completed=%d expected≈%d",
        measured_count,
        completed,
        expected_count,
    )

    assert completed > 0, (
        "CH0 did not complete a measurement"
    )

    assert measured_count > 0, (
        "CH0 measured count remained zero"
    )

    assert_count_close(
        measured_count,
        expected_count,
        "CH0",
    )

    assert ch1_count == 0, (
        f"CH1 count changed while disabled: {ch1_count}"
    )

    assert ch1_completed == 0, (
        f"CH1 completion count changed while disabled: "
        f"{ch1_completed}"
    )

    signal_task.kill()


# ---------------------------------------------------------------------------
# Test 3: Channel 1 end-to-end
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_ch1_spi_end_to_end(dut):
    """
    Configure CH1 through SPI, drive CH1, and read its result through SPI.

    CH0 remains disabled.
    """

    await start_reference_clock(dut)
    await reset_dut(dut)

    gate_cycles = 3

    # Exactly 62 simulated reference-clock periods.
    signal_period_ref_clocks = 62
    signal_period_ns = (
        signal_period_ref_clocks
        * REF_CLK_PERIOD_NS
    )

    expected_count = (
        gate_cycles
        * signal_period_ref_clocks
    )

    await configure_channel(
        dut,
        channel=1,
        gate_cycles=gate_cycles,
        timeout_refcount=10_000,
    )

    assert await spi_read_register(
        dut,
        ADDR_CH0_GATE_CYCLES,
    ) == 0

    signal_task = cocotb.start_soon(
        drive_square_wave(
            dut.ch1_signal_in,
            period_ns=signal_period_ns,
            start_delay_ns=517,
        )
    )

    completed = await wait_for_measurement(
        dut,
        ADDR_CH1_MEASUREMENT_COUNT,
    )

    measured_count = await spi_read_register(
        dut,
        ADDR_CH1_COUNT,
    )

    ch0_count = await spi_read_register(
        dut,
        ADDR_CH0_COUNT,
    )

    ch0_completed = await spi_read_register(
        dut,
        ADDR_CH0_MEASUREMENT_COUNT,
    )

    dut._log.info(
        "CH1 count=%d completed=%d expected≈%d",
        measured_count,
        completed,
        expected_count,
    )

    assert completed > 0, (
        "CH1 did not complete a measurement"
    )

    assert measured_count > 0, (
        "CH1 measured count remained zero"
    )

    assert_count_close(
        measured_count,
        expected_count,
        "CH1",
    )

    assert ch0_count == 0, (
        f"CH0 count changed while disabled: {ch0_count}"
    )

    assert ch0_completed == 0, (
        f"CH0 completion count changed while disabled: "
        f"{ch0_completed}"
    )

    signal_task.kill()


# ---------------------------------------------------------------------------
# Test 4: Simultaneous two-channel operation
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_dual_channel_spi_operation(dut):
    """
    Run both reciprocal channels simultaneously.

    Each channel uses a different sensor period and gate-cycle setting.
    Configuration and result reads are performed entirely through SPI.
    """

    await start_reference_clock(dut)
    await reset_dut(dut)

    ch0_gate_cycles = 4
    ch1_gate_cycles = 3

    ch0_period_ref_clocks = 40
    ch1_period_ref_clocks = 62

    ch0_period_ns = (
        ch0_period_ref_clocks
        * REF_CLK_PERIOD_NS
    )

    ch1_period_ns = (
        ch1_period_ref_clocks
        * REF_CLK_PERIOD_NS
    )

    ch0_expected_count = (
        ch0_gate_cycles
        * ch0_period_ref_clocks
    )

    ch1_expected_count = (
        ch1_gate_cycles
        * ch1_period_ref_clocks
    )

    await configure_channel(
        dut,
        channel=0,
        gate_cycles=ch0_gate_cycles,
        timeout_refcount=10_000,
    )

    await configure_channel(
        dut,
        channel=1,
        gate_cycles=ch1_gate_cycles,
        timeout_refcount=10_000,
    )

    ch0_task = cocotb.start_soon(
        drive_square_wave(
            dut.ch0_signal_in,
            period_ns=ch0_period_ns,
            start_delay_ns=311,
        )
    )

    ch1_task = cocotb.start_soon(
        drive_square_wave(
            dut.ch1_signal_in,
            period_ns=ch1_period_ns,
            start_delay_ns=517,
        )
    )

    ch0_completed = await wait_for_measurement(
        dut,
        ADDR_CH0_MEASUREMENT_COUNT,
    )

    ch1_completed = await wait_for_measurement(
        dut,
        ADDR_CH1_MEASUREMENT_COUNT,
    )

    ch0_count = await spi_read_register(
        dut,
        ADDR_CH0_COUNT,
    )

    ch1_count = await spi_read_register(
        dut,
        ADDR_CH1_COUNT,
    )

    dut._log.info(
        "Dual-channel results: "
        "CH0 count=%d completed=%d expected≈%d; "
        "CH1 count=%d completed=%d expected≈%d",
        ch0_count,
        ch0_completed,
        ch0_expected_count,
        ch1_count,
        ch1_completed,
        ch1_expected_count,
    )

    assert ch0_completed > 0, (
        "CH0 did not complete a measurement"
    )

    assert ch1_completed > 0, (
        "CH1 did not complete a measurement"
    )

    assert ch0_count > 0, (
        "CH0 measured count remained zero"
    )

    assert ch1_count > 0, (
        "CH1 measured count remained zero"
    )

    assert_count_close(
        ch0_count,
        ch0_expected_count,
        "CH0",
    )

    assert_count_close(
        ch1_count,
        ch1_expected_count,
        "CH1",
    )

    assert ch0_count != ch1_count, (
        "The two channels unexpectedly returned identical results"
    )

    ch0_task.kill()
    ch1_task.kill()