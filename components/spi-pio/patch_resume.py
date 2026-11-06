"""Restore LPSS private register state across S3 on PCI-enumerated LPT/WPT SSP.

On MacBook8,1 the LPSS power well is cut in S3, so the SSP's private registers
(lpss_base + 0x00..0x14: clock divider, resets, general, ssp, ...) come back
zeroed and the block is held in reset. Any SSP MMIO access in that state
(including from the shared IRQ 21, also used by the Bluetooth UART) causes a
PCIe completion timeout and a watchdog reset. In ACPI mode acpi_lpss.c saves
and restores this context; in PCI mode nobody does.

This mirrors "spi: pxa2xx: restore LPSS private register state on S3 resume"
(v6, July 2026):
  suspend: save priv 0x00..0x14 after the SSP is disabled, mark suspended
  resume:  de-assert resets (priv 0x04 = 0x3), restore 0x00..0x14, redo
           lpss_ssp_setup() (CS control at 0x18), then clear suspended
  ssp_int: ignore interrupts while suspended

usage: patch_resume.py spi-pxa2xx.c spi-pxa2xx.h
"""
import sys

c_path, h_path = sys.argv[1], sys.argv[2]

# --- header: context storage ---------------------------------------------------
h = open(h_path).read()
anchor = "\tvoid __iomem *lpss_base;\n"
assert h.count(anchor) == 1, "lpss_base field not found"
h = h.replace(anchor, anchor +
              "\n\t/* LPSS private register context saved across system sleep */\n"
              "\tu32 lpss_priv_ctx[6];\n"
              "\tbool lpss_ctx_valid;\n"
              "\tbool suspended;\n", 1)
open(h_path, "w").write(h)

# --- core ------------------------------------------------------------------------
c = open(c_path).read()

# 1. ssp_int: bail out while system-suspended (block may be in reset)
old = "\tif (pm_runtime_suspended(drv_data->ssp->dev))\n\t\treturn IRQ_NONE;\n"
assert c.count(old) == 1, "ssp_int RPM check not found"
c = c.replace(old, "\tif (READ_ONCE(drv_data->suspended))\n\t\treturn IRQ_NONE;\n\n" + old, 1)

# 2. helpers, placed right before pxa2xx_spi_suspend
helpers = r'''
#define LPSS_PRIV_RESETS		0x04
#define LPSS_PRIV_RESETS_FUNC		BIT(0)
#define LPSS_PRIV_RESETS_IDMA		BIT(1)
#define LPSS_PRIV_CTX_REGS		6	/* 0x00..0x14; 0x18 (CS) redone by lpss_ssp_setup() */

static void lpss_ssp_save_ctx(struct driver_data *drv_data)
{
	int i;

	if (!is_lpss_ssp(drv_data) || !drv_data->lpss_base)
		return;
	for (i = 0; i < LPSS_PRIV_CTX_REGS; i++)
		drv_data->lpss_priv_ctx[i] = __lpss_ssp_read_priv(drv_data, i * 4);
	drv_data->lpss_ctx_valid = true;
}

static void lpss_ssp_restore_ctx(struct driver_data *drv_data)
{
	int i;

	if (!is_lpss_ssp(drv_data) || !drv_data->lpss_base || !drv_data->lpss_ctx_valid)
		return;
	/* Take the block out of reset before touching anything else */
	__lpss_ssp_write_priv(drv_data, LPSS_PRIV_RESETS,
			      LPSS_PRIV_RESETS_FUNC | LPSS_PRIV_RESETS_IDMA);
	for (i = 0; i < LPSS_PRIV_CTX_REGS; i++)
		__lpss_ssp_write_priv(drv_data, i * 4, drv_data->lpss_priv_ctx[i]);
	lpss_ssp_setup(drv_data);
}

static int pxa2xx_spi_suspend(struct device *dev)
'''
old = "\nstatic int pxa2xx_spi_suspend(struct device *dev)\n"
assert c.count(old) == 1
c = c.replace(old, helpers, 1)

# 3. suspend: save after the SSP is disabled, before clocks go away
old = "\tpxa_ssp_disable(ssp);\n\n\tif (!pm_runtime_suspended(dev))\n\t\tclk_disable_unprepare(ssp->clk);\n\n\treturn 0;\n}\n"
assert c.count(old) == 1, "suspend body not as expected"
c = c.replace(old,
              "\tpxa_ssp_disable(ssp);\n\n"
              "\tWRITE_ONCE(drv_data->suspended, true);\n"
              "\tsynchronize_irq(ssp->irq);\n"
              "\tlpss_ssp_save_ctx(drv_data);\n\n"
              "\tif (!pm_runtime_suspended(dev))\n\t\tclk_disable_unprepare(ssp->clk);\n\n\treturn 0;\n}\n", 1)

# 4. resume: restore once the clock is on, then let the queue run
old = ("\t/* Enable the SSP clock */\n\tif (!pm_runtime_suspended(dev)) {\n"
       "\t\tstatus = clk_prepare_enable(ssp->clk);\n\t\tif (status)\n\t\t\treturn status;\n\t}\n\n"
       "\t/* Start the queue running */\n\treturn spi_controller_resume(drv_data->controller);\n}\n")
assert c.count(old) == 1, "resume body not as expected"
c = c.replace(old,
              "\t/* Enable the SSP clock */\n\tif (!pm_runtime_suspended(dev)) {\n"
              "\t\tstatus = clk_prepare_enable(ssp->clk);\n\t\tif (status)\n\t\t\treturn status;\n\t}\n\n"
              "\tlpss_ssp_restore_ctx(drv_data);\n"
              "\tWRITE_ONCE(drv_data->suspended, false);\n\n"
              "\t/* Start the queue running */\n"
              "\tstatus = spi_controller_resume(drv_data->controller);\n"
              "\tif (status) {\n"
              "\t\tWRITE_ONCE(drv_data->suspended, true);\n"
              "\t\tsynchronize_irq(ssp->irq);\n"
              "\t}\n"
              "\treturn status;\n}\n", 1)

open(c_path, "w").write(c)
print("patched: LPSS S3 context save/restore")
