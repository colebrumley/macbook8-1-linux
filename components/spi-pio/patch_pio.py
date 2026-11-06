import sys

p = sys.argv[1]
s = open(p).read()

s = s.replace("#include <linux/device.h>\n", "#include <linux/device.h>\n#include <linux/dmi.h>\n", 1)

helper = r'''
static bool force_pio;
module_param(force_pio, bool, 0444);
MODULE_PARM_DESC(force_pio, "Disable DMA and use PIO for all transfers");

static const struct dmi_system_id pxa2xx_spi_pci_no_dma[] = {
	{
		/* MacBook8,1: LPSS DMA handshake/IRQs never complete (bz 108331) */
		.matches = {
			DMI_MATCH(DMI_SYS_VENDOR, "Apple Inc."),
			DMI_MATCH(DMI_PRODUCT_NAME, "MacBook8,1"),
		},
	},
	{ }
};

static bool pxa2xx_spi_pci_no_dma_quirk(void)
{
	return force_pio || dmi_check_system(pxa2xx_spi_pci_no_dma);
}

static bool pxa2xx_spi_pci_can_dma(struct pci_dev *dev)
{
	if (pxa2xx_spi_pci_no_dma_quirk()) {
		dev_info(&dev->dev, "DMA disabled (MacBook8,1 quirk / force_pio), using PIO\n");
		return false;
	}
	return true;
}

static int lpss_spi_setup('''

assert "\nstatic int lpss_spi_setup(" in s
s = s.replace("\nstatic int lpss_spi_setup(", helper, 1)

assert s.count("\tc->enable_dma = 1;\n") == 2
s = s.replace("\tc->enable_dma = 1;\n", "\tc->enable_dma = pxa2xx_spi_pci_can_dma(dev);\n")

assert s.count("\tpm_runtime_allow(&dev->dev);\n") == 1
s = s.replace(
    "\tpm_runtime_allow(&dev->dev);\n",
    "\t/* Runtime-suspended LPSS + PIO MMIO access hangs the bus on MacBook8,1 */\n"
    "\tif (!pxa2xx_spi_pci_no_dma_quirk())\n\t\tpm_runtime_allow(&dev->dev);\n",
)

open(p, "w").write(s)
print("patched")
