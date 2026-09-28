// SPDX-License-Identifier: GPL-2.0+
/*
 * Special Initializers for certain USB Mass Storage devices
 *
 * Current development and maintenance by:
 *   (c) 1999, 2000 Matthew Dharm (mdharm-usb@one-eyed-alien.net)
 *
 * This driver is based on the 'USB Mass Storage Class' document. This
 * describes in detail the protocol used to communicate with such
 * devices.  Clearly, the designers had SCSI and ATAPI commands in
 * mind when they created this document.  The commands are all very
 * similar to commands in the SCSI-II and ATAPI specifications.
 *
 * It is important to note that in a number of cases this class
 * exhibits class-specific exemptions from the USB specification.
 * Notably the usage of NAK, STALL and ACK differs from the norm, in
 * that they are used to communicate wait, failed and OK on commands.
 *
 * Also, for certain devices, the interrupt endpoint is used to convey
 * status of a command.
 */

#include <linux/errno.h>
#include <linux/slab.h>

#include "usb.h"
#include "initializers.h"
#include "debug.h"
#include "transport.h"

/*
 * This places the Shuttle/SCM USB<->SCSI bridge devices in multi-target
 * mode
 */
int usb_stor_euscsi_init(struct us_data *us)
{
	int result;

	usb_stor_dbg(us, "Attempting to init eUSCSI bridge...\n");
	result = usb_stor_control_msg(us, us->send_ctrl_pipe,
			0x0C, USB_RECIP_INTERFACE | USB_TYPE_VENDOR,
			0x01, 0x0, NULL, 0x0, 5 * HZ);
	usb_stor_dbg(us, "-- result is %d\n", result);

	return 0;
}

/*
 * This function is required to activate all four slots on the UCR-61S2B
 * flash reader
 */
int usb_stor_ucr61s2b_init(struct us_data *us)
{
	struct bulk_cb_wrap *bcb = (struct bulk_cb_wrap*) us->iobuf;
	struct bulk_cs_wrap *bcs = (struct bulk_cs_wrap*) us->iobuf;
	int res;
	unsigned int partial;
	static char init_string[] = "\xec\x0a\x06\x00$PCCHIPS";

	usb_stor_dbg(us, "Sending UCR-61S2B initialization packet...\n");

	bcb->Signature = cpu_to_le32(US_BULK_CB_SIGN);
	bcb->Tag = 0;
	bcb->DataTransferLength = cpu_to_le32(0);
	bcb->Flags = bcb->Lun = 0;
	bcb->Length = sizeof(init_string) - 1;
	memset(bcb->CDB, 0, sizeof(bcb->CDB));
	memcpy(bcb->CDB, init_string, sizeof(init_string) - 1);

	res = usb_stor_bulk_transfer_buf(us, us->send_bulk_pipe, bcb,
			US_BULK_CB_WRAP_LEN, &partial);
	if (res)
		return -EIO;

	usb_stor_dbg(us, "Getting status packet...\n");
	res = usb_stor_bulk_transfer_buf(us, us->recv_bulk_pipe, bcs,
			US_BULK_CS_WRAP_LEN, &partial);
	if (res)
		return -EIO;

	return 0;
}

/* This places the HUAWEI E220 devices in multi-port mode */
int usb_stor_huawei_e220_init(struct us_data *us)
{
	int result;

	result = usb_stor_control_msg(us, us->send_ctrl_pipe,
				      USB_REQ_SET_FEATURE,
				      USB_TYPE_STANDARD | USB_RECIP_DEVICE,
				      0x01, 0x0, NULL, 0x0, 1 * HZ);
	usb_stor_dbg(us, "Huawei mode set result is %d\n", result);
	return 0;
}

/*
 * Many cheap USB WiFi dongles (Realtek RTL8811CU/RTL8821CU/RTL8188GU,
 * MediaTek MT7601U, ...) power up as a virtual CD-ROM carrying the
 * Windows driver and only switch to WiFi mode after a SCSI eject.
 * Android has no usb_modeswitch, so send a START STOP UNIT (eject)
 * from here and refuse to bind as storage.
 */
int usb_stor_wifi_eject_init(struct us_data *us)
{
	struct bulk_cb_wrap *bcb = (struct bulk_cb_wrap *) us->iobuf;
	struct bulk_cs_wrap *bcs = (struct bulk_cs_wrap *) us->iobuf;
	static const u8 eject_cmd[] = { 0x1b, 0x00, 0x00, 0x00, 0x02, 0x00 };
	unsigned int partial;
	int res;

	usb_stor_dbg(us, "Ejecting WiFi dongle virtual CD-ROM...\n");

	bcb->Signature = cpu_to_le32(US_BULK_CB_SIGN);
	bcb->Tag = 0;
	bcb->DataTransferLength = cpu_to_le32(0);
	bcb->Flags = bcb->Lun = 0;
	bcb->Length = sizeof(eject_cmd);
	memset(bcb->CDB, 0, sizeof(bcb->CDB));
	memcpy(bcb->CDB, eject_cmd, sizeof(eject_cmd));

	res = usb_stor_bulk_transfer_buf(us, us->send_bulk_pipe, bcb,
			US_BULK_CB_WRAP_LEN, &partial);
	usb_stor_dbg(us, "-- eject CBW result is %d\n", res);
	if (res == USB_STOR_XFER_GOOD)
		usb_stor_bulk_transfer_buf(us, us->recv_bulk_pipe, bcs,
				US_BULK_CS_WRAP_LEN, &partial);

	dev_info(&us->pusb_dev->dev, "WiFi dongle switched out of CD-ROM mode\n");

	/* The device drops off the bus and comes back as WiFi */
	return -ENODEV;
}

/*
 * Modems and dongles that start as a virtual CD-ROM (unusual_modeswitch.h).
 * The switch commands come from usb-modeswitch-data. Plain usb_bulk_msg()
 * with a timeout is used so a device that neither answers nor drops off
 * the bus can't hang the probe.
 */
struct usb_stor_modeswitch {
	u16 id_vendor;
	u16 id_product;
	const char *cbw;	/* NULL: standard SCSI eject */
};

static const struct usb_stor_modeswitch usb_stor_modeswitch_list[] = {
#define MODESWITCH_EJECT(id_vendor, id_product) \
	{ id_vendor, id_product, NULL },
#define MODESWITCH_MSG(id_vendor, id_product, msg) \
	{ id_vendor, id_product, msg },
#define MODESWITCH_OPTION(id_vendor, id_product)
#include "unusual_modeswitch.h"
#undef MODESWITCH_EJECT
#undef MODESWITCH_MSG
#undef MODESWITCH_OPTION
};

/* usb_modeswitch's StandardEject: ALLOW MEDIUM REMOVAL, then START STOP UNIT eject */
static const char usb_stor_modeswitch_allow_removal[] =
	"\x55\x53\x42\x43\x12\x34\x56\x78\x00\x00\x00\x00\x00\x00\x06\x1e"
	"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00";
static const char usb_stor_modeswitch_eject[] =
	"\x55\x53\x42\x43\x12\x34\x56\x79\x00\x00\x00\x00\x00\x00\x06\x1b"
	"\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00";

static int usb_stor_modeswitch_send(struct us_data *us, u8 *buf, const char *cbw)
{
	int len = 0;
	int res;

	memcpy(buf, cbw, US_BULK_CB_WRAP_LEN);
	res = usb_bulk_msg(us->pusb_dev, us->send_bulk_pipe, buf,
			US_BULK_CB_WRAP_LEN, &len, 1000);
	if (res)
		return res;
	/* Data and/or status, if the device still answers; errors don't matter */
	usb_bulk_msg(us->pusb_dev, us->recv_bulk_pipe, buf, 64, &len, 500);
	return 0;
}

int usb_stor_modeswitch_init(struct us_data *us)
{
	u16 vid = le16_to_cpu(us->pusb_dev->descriptor.idVendor);
	u16 pid = le16_to_cpu(us->pusb_dev->descriptor.idProduct);
	const struct usb_stor_modeswitch *ms = NULL;
	struct usb_host_config *config;
	unsigned int i;
	u8 *buf;
	int res;

	for (i = 0; i < ARRAY_SIZE(usb_stor_modeswitch_list); i++) {
		if (usb_stor_modeswitch_list[i].id_vendor == vid &&
		    usb_stor_modeswitch_list[i].id_product == pid) {
			ms = &usb_stor_modeswitch_list[i];
			break;
		}
	}
	if (!ms)
		return 0;

	config = us->pusb_dev->actconfig;
	if (!config)
		return -ENODEV;

	/*
	 * Some devices keep their ID after switching. If anything other than
	 * mass storage is there, it is already in modem mode: only keep a
	 * real storage interface (e.g. a microSD slot), and send nothing.
	 */
	for (i = 0; i < config->desc.bNumInterfaces; i++) {
		if (config->interface[i]->cur_altsetting->desc.bInterfaceClass !=
		    USB_CLASS_MASS_STORAGE)
			return us->pusb_intf->cur_altsetting->desc.bInterfaceClass ==
				USB_CLASS_MASS_STORAGE ? 0 : -ENODEV;
	}

	/* Like usb_modeswitch, talk to the first mass storage interface only */
	if (config->interface[0] != us->pusb_intf)
		return -ENODEV;

	buf = kmalloc(64, GFP_NOIO);
	if (!buf)
		return -ENOMEM;

	if (ms->cbw) {
		res = usb_stor_modeswitch_send(us, buf, ms->cbw);
	} else {
		usb_stor_modeswitch_send(us, buf, usb_stor_modeswitch_allow_removal);
		res = usb_stor_modeswitch_send(us, buf, usb_stor_modeswitch_eject);
	}
	kfree(buf);

	dev_info(&us->pusb_dev->dev, "%04x:%04x: %s CD-ROM mode switch %s\n",
		 vid, pid, ms->cbw ? "modem" : "eject",
		 res ? "failed" : "sent");

	/* The device drops off the bus and comes back in modem mode */
	return -ENODEV;
}
