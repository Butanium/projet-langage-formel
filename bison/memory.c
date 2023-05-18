#include "hash.c"
#include "crc32.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "memory.h"
/***************************************************************************/
/* Data structures for storing a programme.                                */

void yyerror(char *s)
{
	fflush(stdout);
	fprintf(stderr, "%s\n", s);
}

