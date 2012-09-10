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

static int debug_level = DBG_VERBOSE;
FILE *debug_dest;

void _debug_syserr(int level, const char *func, const char *file, int line, const char *fmt, ...)
{
	if (level <= debug_level) {
		char *buf;
		va_list va;
		va_start(va, fmt);
		vasprintf(&buf, fmt, va);
		fprintf(debug_dest, "ERR %s (%s:%d) %s: %s\n", func, file, line, buf, strerror(errno));
		va_end(va);
		free(buf);
	}
}

void _debug(int level, const char *func, const char *file, int line, const char *fmt, ...)
{
	if (level <= debug_level) {
		char *buf;
		va_list va;
		va_start(va, fmt);
		vasprintf(&buf, fmt, va);
		fprintf(debug_dest, "DBG %s (%s:%d) %s\n", func, file, line, buf);
		va_end(va);
		free(buf);
	}
}

void _debug_setup_logfile(char *logfile)
{
	if ((debug_dest = fopen(logfile, "w")) == NULL)
		debug_dest = stderr;
}

const char *err_str(int code)
{
	if (code < 0)
		code = -code;
	switch (code) {
		case OK:                    return "No error";
		case ERR_BUSY:              return "Attempted to use device while it is already in use";
		case ERR_INVALID_RESPONSE:  return "Invalid response code received from device";
		case ERR_NO_START_BYTE:     return "No start byte received from device";
		case ERR_NO_RESPONSE:       return "No response received from device";
		case ERR_OPEN_SERIAL_DEV:   return "Serial device open failed";
		case ERR_CLOSE_SERIAL_DEV:  return "Serial device close failed";
		case ERR_WRITE_SERIAL_DEV:  return "Write to serial device failed";
		case ERR_READ_SERIAL_DEV:   return "Read from serial device failed";
		case ERR_NOT_INITIALISED:   return "Device was not initialised before call";
		case ERR_PARAM_INVALID:     return "One or more passed parameters were invalid or out of range";
		case ERR_STATE_INVALID:     return "Current device state is invalid for the requested command";
		default:                    return "Unknown error";
	}
}
/* timeout is in sec */
int read_byte_with_timeout(int fd, byte *b, long sec)
{
	fd_set readset;
	struct timeval tv, *tvp;
	int rv, ret;

	tv.tv_sec = sec;
	tv.tv_usec = 0;

	if (sec > 0)
		tvp = &tv;
	else
		tvp = NULL;

	while (1)
	{
		FD_ZERO(&readset);
		FD_SET(fd, &readset);
		
		rv = select(fd + 1, &readset, NULL, NULL, tvp);

		if (rv == 0) {
			debug(DBG_ANAL, "Read timed out after %d seconds", sec);
			return -ERR_READ_TIMEOUT;
		}
		
		if (rv > 0)
		{
			if (FD_ISSET(fd, &readset))
			{
				ret = read(fd, b, sizeof(byte));
				if (ret < 0)
				{
					debug_syserr(DBG_VERBOSE, "read(serialfd)");
					return -ERR_READ_SERIAL_DEV;
				}
				if (ret != sizeof(byte))
				{
					debug(DBG_VERBOSE, "Read %d bytes, but only %d were expected.", ret, sizeof(byte));
					return -ERR_DATA_LEN;
				}
				return OK;
			}
		}
	}
}

int recv_byte(int fd, byte *b)
{
	return read_byte_with_timeout(fd, b, 10);
}

int send_byte(int fd, byte b)
{
	int ret = write(fd, &b, sizeof(byte));
	if (ret < 0)
	{
		debug_syserr(DBG_VERBOSE, "write(fd)");
		return -ERR_WRITE_SERIAL_DEV;
	}
	if (ret != sizeof(byte))
	{
		debug(DBG_VERBOSE, "Wrote %d bytes, but only %d were sent.", ret, sizeof(byte));
		return -ERR_DATA_LEN;
	}

	return OK;
}


