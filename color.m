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
#include <ncurses.h>
#include <stdlib.h>
#include "color.h"

unsigned PairCount = 1;

PairList *Pairs[MAX_PAIRS];

inline int Pair(short fg, short bg)
{
	int i;

	for (i = 1; i < PairCount; i++)
		if (Pairs[i]->fore_color == fg && Pairs[i]->back_color == bg)
			return COLOR_PAIR(Pairs[i]->Pair);

	Pairs[PairCount] = (PairList *) malloc(sizeof(PairList));
	Pairs[PairCount]->Pair = PairCount;
	
	init_pair(Pairs[PairCount]->Pair, fg, bg);

	Pairs[PairCount]->fore_color = fg;
	Pairs[PairCount]->back_color = bg;

	return COLOR_PAIR(Pairs[PairCount++]->Pair);
}

void free_pairs(void)
{
	int i;
	for(i = 0; i < PairCount; i++)
		free(Pairs[i]);
	
	PairCount = 0;
}
