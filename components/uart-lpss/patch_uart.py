"""Add system-sleep PM ops to 8250_lpss (it has none).

On MacBook8,1 the LPSS power well is cut in S3. The Wildcat Point UART (00:15.5,
Bluetooth) comes back with its LPSS private RESETS register (+0x804) = 0, i.e.
held in reset, and with all 16550 state lost. 8250_lpss has no PM ops, so the
port is never suspended/resumed: Bluetooth then fails with "command 0x0c01 tx
timeout" after every resume.

suspend: serial8250_suspend_port()
resume:  de-assert LPSS resets, re-mask TX overflow IRQ (byt/bdw boards),
         then serial8250_resume_port() (reprograms clock divider via
         byt_set_termios, LCR/DLL, IER/MCR)

usage: patch_uart.py 8250_lpss.c
"""
import sys

p = sys.argv[1]
s = open(p).read()

pm = r'''
#define LPSS_PRV_RESETS			0x804
#define LPSS_PRV_RESETS_FUNC		BIT(0)
#define LPSS_PRV_RESETS_IDMA		BIT(1)

static int lpss8250_suspend(struct device *dev)
{
	struct lpss8250 *lpss = dev_get_drvdata(dev);

	serial8250_suspend_port(lpss->data.line);
	return 0;
}

static int lpss8250_resume(struct device *dev)
{
	struct lpss8250 *lpss = dev_get_drvdata(dev);
	struct uart_8250_port *up = serial8250_get_port(lpss->data.line);

	if (lpss->board == &byt_board) {
		/* Power well was cut: the block is held in reset, private regs lost */
		writel(LPSS_PRV_RESETS_FUNC | LPSS_PRV_RESETS_IDMA,
		       up->port.membase + LPSS_PRV_RESETS);
		writel(BYT_TX_OVF_INT_MASK, up->port.membase + BYT_TX_OVF_INT);
	}

	serial8250_resume_port(lpss->data.line);
	return 0;
}

static DEFINE_SIMPLE_DEV_PM_OPS(lpss8250_pm_ops, lpss8250_suspend, lpss8250_resume);

static struct pci_driver lpss8250_pci_driver = {'''

old = "\nstatic struct pci_driver lpss8250_pci_driver = {"
assert s.count(old) == 1, "pci_driver not found"
s = s.replace(old, pm, 1)

old = "\t.remove         = lpss8250_remove,\n"
assert s.count(old) == 1, "remove hook not found"
s = s.replace(old, old + "\t.driver.pm      = pm_sleep_ptr(&lpss8250_pm_ops),\n", 1)

assert "pm_sleep_ptr(&lpss8250_pm_ops)" in s
open(p, "w").write(s)
print("patched: 8250_lpss system-sleep PM ops")
