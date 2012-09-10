/* 
 * Ecstazy Nissan 300ZX Diagnostic Tuning Suite
 *
 * Copyright (C) 2003-2009   Patrick Cole <z@amused.net>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#include "common.h"

#define WBO2_CHECK_INITIALISED() \
	if (WBO2Config.initialised == FALSE) { \
		debug(DBG_ANAL, "Called without initialising"); \
		return -ERR_NOT_INITIALISED; \
	}

#define WBO2_CHECK_BUSY() \
	if (WBO2Config.streaming == TRUE) { \
		debug(DBG_ANAL, "Called while already streaming"); \
		return -ERR_BUSY; \
	}

struct {
	int serialfd;
	bool initialised;
	bool streaming;
	WBO2MonitorCallback mon_data_callback;
	void *mon_data_callback_arg;
	char buffer[200];
	int bufpos;
} WBO2Config = {
	.initialised = FALSE,
	.streaming = FALSE,
	.bufpos = 0,
};

int wbo2_init(const char *dev, int init_tries)
{
	struct termios term;
	
	/* open port */
	if ((WBO2Config.serialfd = open(dev, O_RDWR)) < 0)
	{
		WBO2Config.initialised = FALSE;
		debug_syserr(DBG_VERBOSE, "open(%s) failed", dev);
		return -ERR_OPEN_SERIAL_DEV;
	}

	/* set serial parameters */
	memset(&term, 0, sizeof(term));
	tcgetattr(WBO2Config.serialfd, &term);
	cfmakeraw(&term);
	term.c_iflag &= ~(INPCK|ICRNL|INPCK);
	term.c_lflag &= ~(ECHO);
	term.c_cflag |= CRTSCTS;
	cfsetispeed(&term, B9600);
	cfsetospeed(&term, B9600);
	tcsetattr(WBO2Config.serialfd, 0, &term);

	WBO2Config.initialised = TRUE;

	debug(DBG_VERBOSE, "WBO2 successfully initialised");

	return RET_OK;
}

int wbo2_close()
{
	debug(DBG_VERBOSE, "Closing WBO2 connection");
	if (WBO2Config.initialised == TRUE) {
		if (WBO2Config.streaming == TRUE) {
			debug(DBG_VERBOSE, "Stopping data stream");
			WBO2Config.streaming = FALSE;
		}
		if (close(WBO2Config.serialfd) < 0) {
			debug_syserr(DBG_VERBOSE, "Close serial port failed");
			WBO2Config.initialised = FALSE;
			return -ERR_CLOSE_SERIAL_DEV;
		} else {
			WBO2Config.initialised = FALSE;
			return RET_OK;
		}
	} else {
		debug(DBG_VERBOSE, "Called without WBO2 being initialised");
		return -ERR_NOT_INITIALISED;
	}
}


int wbo2_get_fd()
{
	WBO2_CHECK_INITIALISED();
	return WBO2Config.serialfd;
}

int wbo2_start_monitor(WBO2MonitorCallback my_data_callback, void *my_arg)
{
	WBO2_CHECK_INITIALISED();
	WBO2_CHECK_BUSY();

	WBO2Config.mon_data_callback = my_data_callback;
	WBO2Config.mon_data_callback_arg = my_arg;
	WBO2Config.buffer[0] = 0;
	WBO2Config.bufpos = 0;

	// ready for stream data now
	WBO2Config.streaming = TRUE;

	return RET_OK;
}

int wbo2_stop_monitor()
{
	WBO2_CHECK_INITIALISED();

	if (WBO2Config.streaming == TRUE) {
		WBO2Config.streaming = FALSE;
		return RET_OK;
	}

	return -ERR_STATE_INVALID;
}

int wbo2_process_data_from_fd()
{
	byte b;
	char afrbuf[5];

	WBO2_CHECK_INITIALISED();

	if (recv_byte(WBO2Config.serialfd, &b) != RET_OK)
	{
		debug(DBG_VERBOSE, "Failed to receive data from serial FD");
		return -ERR_INVALID_RESPONSE;
	}

	if (WBO2Config.bufpos + 1 > 200) {
		WBO2Config.buffer[0] = WBO2Config.buffer[WBO2Config.bufpos-3];
		WBO2Config.buffer[1] = WBO2Config.buffer[WBO2Config.bufpos-2];
		WBO2Config.buffer[2] = WBO2Config.buffer[WBO2Config.bufpos-1];
		WBO2Config.bufpos = 3;
	}

	WBO2Config.buffer[WBO2Config.bufpos++] = b;

	if (WBO2Config.bufpos >= 4 && 
			isdigit(WBO2Config.buffer[WBO2Config.bufpos-1]) &&
			WBO2Config.buffer[WBO2Config.bufpos-2] == '.' &&
			isdigit(WBO2Config.buffer[WBO2Config.bufpos-3]) &&
			isdigit(WBO2Config.buffer[WBO2Config.bufpos-4])) {
		memcpy(afrbuf, WBO2Config.buffer + WBO2Config.bufpos - 4, 4);
		afrbuf[4] = 0;
		WBO2Config.mon_data_callback(strtof(afrbuf, NULL), WBO2Config.mon_data_callback_arg);
	}

	return RET_OK;
}


