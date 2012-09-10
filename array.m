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
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <assert.h>
#import "array.h"

@implementation _array

+ new
{
	self = [super new];
	[self init];
	return self;
}

- init
{
	memory = (void **) 0;
	size = 0;
	return self;
}

- free: (void (*)(void *)) user_free_func
{
	int i;
	for (i = 0; i < size; i++)
		user_free_func(*(memory + i));
	free(memory);
	return self;
}

- (int) length
{
	return size;
}

- resize: (int) new_size
{
	int i;
	memory = realloc(memory, sizeof(void **) * new_size);
	if (new_size > size)
		for (i = size; i < new_size; i++)
			*(memory + i) = NULL;
	size = new_size;
	return self;
}

- set: (int) ind data: (void *) data
{
	assert(size > 0);
	if (ind >= size || ind < 0)
		return self;
	*(memory + ind) = data;
	return self;
}

- (void *) get: (int) ind
{
	assert(size > 0);
	if (ind >= size || ind < 0)
		return self;
	return *(memory + ind);
}

- (void *) head
{
	assert(size > 0);
	return *memory;
}

- (void *) tail
{
	assert(size > 0);
	return *(memory + size - 1);
}

- sort: (int (*)(const void *, const void *)) sortf
{
	assert(size > 0);
	qsort(memory, size, sizeof(*memory), sortf);
	return self;
}

@end
