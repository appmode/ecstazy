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
#ifndef _COMMON_H
#define _COMMON_H

#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/select.h>
#include <termios.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdarg.h>
#include <errno.h>
#include <getopt.h>
#include <ncurses.h>
#include <ctype.h>
#include <time.h>
#include <pthread.h>
#include <math.h>
#include <sys/ioctl.h>

#define ECSTAZY_BYTE unsigned char
#define ECSTAZY_WORD unsigned short
#define ECSTAZY_SIGNED_BYTE signed char
#define ECSTAZY_SIGNED_WORD signed short

#if !defined(bool)
  #define bool ECSTAZY_BYTE
#endif

#if !defined(byte)
  #define byte ECSTAZY_BYTE
#endif
#if !defined(signedbyte)
  #define signedbyte ECSTAZY_SIGNED_BYTE
#endif

#if !defined(word)
  #define word ECSTAZY_WORD
#endif
#if !defined(signedword)
  #define signedword ECSTAZY_SIGNED_WORD
#endif

#ifndef TRUE
#define TRUE (1)
#endif

#ifndef FALSE
#define FALSE (0)
#endif

#define MAX(a,b) (a>b?a:b)
#define MIN(a,b) (a<b?a:b)

#define WORD_PACK1(mem, index) (((word)mem[index] << 8) | mem[index + 1])
#define WORD_PACK2(mem, index) (((word)mem[index + 1] << 8) | mem[index])

#define DBG_OFF     (0)
#define DBG_VERBOSE (1)
#define DBG_ANAL    (2)

#ifdef DEBUG
#define debug(level, fmt, args...) _debug(level, __FUNCTION__, __FILE__, __LINE__, fmt, ##args)
#define debug_syserr(level, fmt, args...) _debug_syserr(level, __FUNCTION__, __FILE__, __LINE__, fmt, ##args)
#else
#define debug(level, fmt, args...) do{}while(0)
#define debug_syserr(level, fmt, args...) do{}while(0)
#endif

void _debug_syserr(int level, const char *func, const char *file, int line, const char *fmt, ...);
void _debug(int level, const char *func, const char *file, int line, const char *fmt, ...);
void _debug_setup_logfile(char *logfile);
const char* err_str(int code);
int read_byte_with_timeout(int fd, byte *b, long sec);
int recv_byte(int fd, byte *b);
int send_byte(int fd, byte b);

enum ReturnValue {
	RET_OK = 0,
	READ_OK = 0,
	ERR_READ_TIMEOUT,
	ERR_BUSY,
	ERR_INVALID_RESPONSE,
	ERR_NO_START_BYTE,
	ERR_NO_RESPONSE,
	ERR_OPEN_SERIAL_DEV,
	ERR_CLOSE_SERIAL_DEV,
	ERR_WRITE_SERIAL_DEV,
	ERR_READ_SERIAL_DEV,
	ERR_NOT_INITIALISED,
	ERR_STATE_INVALID,
	ERR_DATA_LEN,
	ERR_PARAM_INVALID
};

#define PRINT_ERROR(ecode) \
	fprintf(stderr, "ECSTAZY ERR (%s:%d) %s\n", __FILE__, __LINE__, err_str(ecode));

#define CHECK_OK(eval) { \
	int ret = eval; \
	if (ret != OK) PRINT_ERROR(ret); \
}

#define ASSERT_OK(eval) { \
	int ret = eval; \
	if (ret != OK) { \
		PRINT_ERROR(ret); \
		exit(ret); \
	} \
}

extern char *ecudev;
extern char *romulatordev;
extern char *wbo2dev;

#include "array.h"
#include "menu.h"
#include "ecu.h"
#include "conv.h"
#include "rom.h"
#include "color.h"
#include "romulator.h"
#include "wbo2.h"

#endif /* _COMMON_H */
