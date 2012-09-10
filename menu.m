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

#define inc_sidx() \
	if (sidx + 1 >= [super length]) { \
		sidx = 0; \
	} else { \
		sidx += 1; \
	}

#define dec_sidx() \
	if (sidx - 1 < 0) { \
		sidx = [super length] - 1; \
	} else { \
		sidx -= 1; \
	}

@implementation _menu

+ new
{
	self = [super new];
	[self init];
	return self;
}

- init
{
	sidx = 0;
	return self;
}


- (int) additem: (char *) text
{
	[super resize: [super length] + 1];
	[super set: [super length] - 1 data: text];
	return [super length] - 1;
}

- (int) select
{
	char *text;
	int c, i, j;
	int maxlen=0;

	for (i = 0; i < [super length]; i++) {
		text = [super get: i];
		if (text != NULL && strlen(text) > maxlen)
			maxlen = strlen(text);
	}

	while (1) {
		erase();

		for (i = 0; i < [super length]; i++) {
			text = [super get: i];
			if (i == sidx)
				attrset(Pair(COLOR_BLACK, COLOR_WHITE));
			else
				attrset(Pair(COLOR_WHITE, COLOR_BLACK));
			mvprintw(i, 0, " %s", text ? text : "");
			if (text != NULL)
				for (j = strlen(text); j < maxlen; j++)
					mvprintw(i, 1 + j, " ");
		}
		
		refresh();

		c = getch();

		switch (c) {
			case KEY_UP:
				dec_sidx();
				if ([super get: sidx] == NULL) {
					dec_sidx();
				}
				break;

			case KEY_DOWN:
				inc_sidx();
				if ([super get: sidx] == NULL) {
					inc_sidx();
				}
				break;

			case '\r':
			case '\n':
			case KEY_ENTER:
				return sidx;
		}
	}
}

@end
