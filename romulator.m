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

#define WRITESZ (0)
#define LOBYTE(w) (byte) ((w & 0x00ff) >> 0)
#define HIBYTE(w) (byte) ((w & 0xff00) >> 8)
#define INIT_TRIES (2)
#define ON (1)
#define OFF (0)

int romu_ready = FALSE;

int romufd;

int setDTR(int on)
{
	int req = (on ? TIOCMSET : TIOCMBIC);
	unsigned long cmd = TIOCM_DTR;
	if (ioctl(romufd, req, &cmd) != 0) {
		debug_syserr(DBG_VERBOSE, "ERROR: ioctl() change DTR failed");
		return -1;
	}
	return 0;
}

int setRTS(int on)
{
	int req = (on ? TIOCMSET : TIOCMBIC);
	unsigned long cmd = TIOCM_RTS;
	if (ioctl(romufd, req, &cmd) != 0) {
		debug_syserr(DBG_VERBOSE, "ERROR: ioctl() change RTS failed");
		return -1;
	}
	return 0;
}

/* timeout is in sec */
int romu_read_byte_with_timeout(byte *b, long sec)
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
		FD_SET(romufd, &readset);
		
		rv = select(romufd + 1, &readset, NULL, NULL, tvp);

		if (rv == 0)
			return ROMU_TIMEOUT;
		
		if (rv > 0)
		{
			if (FD_ISSET(romufd, &readset))
			{
				ret = read(romufd, b, sizeof(byte));
				if (ret < 0)
				{
					perror("romu_read_byte_with_timeout(): read(romufd)");
					exit(errno);
				}
				if (ret != sizeof(byte))
				{
					debug(DBG_VERBOSE, "Error: Read %d bytes, but only %d were expected.", ret, sizeof(byte));
					exit(EMSGSIZE);
				}
				return RET_OK;
			}
		}
	}
}

int romu_readbyte(byte *b)
{
	return romu_read_byte_with_timeout(b, 10);
}

int romu_readword(word *wp)
{
	int ret = 0;
	byte b1, b2;
	ret |= romu_read_byte_with_timeout(&b1, 10);
	ret |= romu_read_byte_with_timeout(&b2, 10);
	*wp = b1;
	*wp <<= 8;
	*wp |= b2;
	return ret;
}

int romu_sendbyte(byte b)
{
	int ret = write(romufd, &b, sizeof(byte));
	if (ret < 0)
	{
		perror("romu_sendbyte(): write(romufd)");
		exit(errno);
	}
	if (ret != sizeof(byte))
	{
		debug(DBG_VERBOSE, "Error: Wrote %d bytes, but only %d were sent.", ret, sizeof(byte));
		exit(EMSGSIZE);
	}
	return RET_OK;
}

int sendword(word w)
{
	int ret = write(romufd, &w, sizeof(word));
	if (ret < 0)
	{
		perror("sendword(): write(romufd)");
		exit(errno);
	}
	if (ret != sizeof(word))
	{
		debug(DBG_VERBOSE, "Error: Wrote %d bytes, but only %d were sent.", ret, sizeof(byte));
		exit(EMSGSIZE);
	}
	return RET_OK;
}

int romu_init()
{
	byte ver[2];
	byte id;
	int try = 0;
	struct termios term;

	// open port
	
	if ((romufd = open(romulatordev, O_RDWR)) < 0)
	{
		debug_syserr(DBG_VERBOSE, "open(%s) failed", romulatordev);
		romu_ready = FALSE;
		return -ROMU_INIT_FAIL;
	}

	// set serial parameters
	
	bzero(&term, sizeof(term));

	tcgetattr(romufd, &term);

	cfmakeraw(&term);

	term.c_iflag &= ~(INPCK|ICRNL|INPCK|IXON|IXOFF);
	term.c_lflag &= ~(ECHO);
	term.c_cflag &= ~(CRTSCTS);

	cfsetispeed(&term, B115200);
	cfsetospeed(&term, B115200);
	
	tcsetattr(romufd, 0, &term);

	// do actual initialisation

	while (try < INIT_TRIES) 
	{
		romu_sendbyte('V');
		romu_sendbyte(0x56); // checksum

		if (romu_read_byte_with_timeout(ver+0, 1) == RET_OK &&
				romu_read_byte_with_timeout(ver+1, 1) == RET_OK &&
				romu_read_byte_with_timeout(&id, 1) == RET_OK)
			break;

		try++;
	}

	if (try < INIT_TRIES)
		debug(DBG_VERBOSE, "Romulator Initialised Ver: %d.%d  ID: %c\n", ver[0], ver[1], id);
	else {
		debug(DBG_VERBOSE, "Romulator failed to initialise");
		romu_ready = FALSE;
		return -ROMU_INIT_FAIL;
	}

	romu_ready = TRUE;

	return RET_OK;
}

int romu_calc_block_size(int len)
{
	int n;
	for (n = len; n > ROMU_BLOCK_SIZE; n--);
	return n;
}

int romu_read_block(word addr, byte *block, word size)
{
	byte checksum;
	byte b;
	int j;

	debug(DBG_ANAL, "Reading %d-byte block at address %04xh...", size, addr);
	fflush(stdout);
		
	romu_sendbyte('R');
	romu_sendbyte(size);
	romu_sendbyte(HIBYTE(addr));
	romu_sendbyte(LOBYTE(addr));

	checksum = 'R' + size + HIBYTE(addr) + LOBYTE(addr);
	romu_sendbyte(checksum);

	checksum = 0;

	bzero(block, size);

	for (j = 0; j < size; j++) 
	{
		if (romu_read_byte_with_timeout(block + j, 5) == ROMU_TIMEOUT) 
		{
			debug(DBG_VERBOSE, "ERROR: readbyte timed out, byte %d", j);
			return -ROMU_TIMEOUT;
		}

		checksum += block[j];
	}

	romu_read_byte_with_timeout(&b, 5);
	if (b != checksum) 
	{
		debug(DBG_VERBOSE, "ERROR: Checksum is incorrect: %d != %d", b, checksum);
		return -ROMU_BAD_CKSUM;
	}

	return RET_OK;
}

int romu_read_buffer(word addr, byte *buffer, word len)
{
	int blksz = romu_calc_block_size(len);
	int i, ret;

	if (!romu_ready) return -1;

	for (i = 0; ((i+1) * blksz) <= len; i += 1) 
		if ((ret = romu_read_block(addr + (i * blksz), buffer + (i * blksz), blksz)) < 0)
			return ret;

	if ((i * blksz) < len)
		if ((ret = romu_read_block(addr + (i * blksz), buffer + (i * blksz), len - (i * blksz))) < 0)
			return ret;

	return RET_OK;
}

int romu_write_block(word addr, byte *block, word size)
{
	int j;
	byte b;
	byte checksum;

	if (!romu_ready) return -1;

	debug(DBG_VERBOSE, "Writing %d-byte block at address %04xh...", ROMU_BLOCK_SIZE, addr);
	fflush(stdout);
		
	romu_sendbyte('W');
	romu_sendbyte(size);
	romu_sendbyte(HIBYTE(addr));
	romu_sendbyte(LOBYTE(addr));

	checksum = 'W' + size + HIBYTE(addr) + LOBYTE(addr);
	
	for (j = 0; j < size; j++) {
		romu_sendbyte(block[j]);
		checksum += block[j];
	}

	romu_sendbyte(checksum);

	romu_readbyte(&b);

	if (b == 0x3f) {
		debug(DBG_VERBOSE, "Romulator command failure");
		return -ROMU_COMMAND_FAIL;
	}
	else if (b != 'O') {
		debug(DBG_VERBOSE, "Romulator command completion was not OK.");
		return -ROMU_COMMAND_FAIL;
	}

	return RET_OK;
}

int romu_write_buffer(word addr, byte *buffer, word len)
{
	int blksz = romu_calc_block_size(len);
	int i, ret;

	if (!romu_ready) return -1;

	for (i = 0; ((i+1) * blksz) <= len; i += 1) 
		if ((ret = romu_write_block(addr + (i * blksz), buffer + (i * blksz), blksz)) < 0)
			return ret;

	if ((i * blksz) < len)
		if ((ret = romu_write_block(addr + (i * blksz), buffer + (i * blksz), len - (i * blksz))) < 0)
			return ret;

	return RET_OK;
}

int romu_hidden_write(word addr, byte data)
{
	byte b;
	byte checksum;

	if (!romu_ready) return -1;

	debug(DBG_VERBOSE, "Hidden write at address %04xh...", addr);
	fflush(stdout);
		
	romu_sendbyte('w');
	romu_sendbyte(1);
	romu_sendbyte(HIBYTE(addr));
	romu_sendbyte(LOBYTE(addr));

	checksum = 'w' + WRITESZ + HIBYTE(addr) + LOBYTE(addr);
	
	romu_sendbyte(data);
	checksum = data;

	romu_sendbyte(checksum);

	romu_readbyte(&b);

	if (b == 0x3f) {
		debug(DBG_VERBOSE, "Romulator command failure");
		return -ROMU_COMMAND_FAIL;
	}
	else if (b != 'O') {
		debug(DBG_VERBOSE, "Romulator command completion was not OK.");
		return -ROMU_COMMAND_FAIL;
	}

	return RET_OK;
}
