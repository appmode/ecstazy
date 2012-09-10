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
#ifndef _WBO2_H
#define _WBO2_H

#define WBO2_PRINT_ERROR(ecode) \
	fprintf(stderr, "WBO2 ERR (%s:%d) %s\n", __FILE__, __LINE__, err_str(ecode));

#define WBO2_CHECK_OK(eval) { \
	int ret = eval; \
	if (ret != WBO2_OK) WBO2_PRINT_ERROR(ret); \
}

#define WBO2_ASSERT_OK(eval) { \
	int ret = eval; \
	if (ret != WBO2_OK) { \
		WBO2_PRINT_ERROR(ret); \
		exit(ret); \
	} \
}

typedef void (*WBO2MonitorCallback)(float afr, void *arg);

/* external prototypes */

int wbo2_init(const char *dev, int init_tries);
int wbo2_close();
int wbo2_process_data_from_fd();
int wbo2_get_fd();
int wbo2_start_monitor(WBO2MonitorCallback my_data_callback, void *my_arg);
int wbo2_stop_monitor();
const char *wbo2_err_str(int code);

#endif

