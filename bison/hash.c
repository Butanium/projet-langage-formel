/*****************************************************************************/
/* Generic hash table + with inbuilt worklist 				     */

/* Typical use case:

	// First write some function that compares two states.
	// The code below uses this to order states inside a hash bucket.
	int states_compare (wState *state1, wState *state2)
	{
		return 0;  // if state1 equal to state2
		return -1; // if state1 is "less than" state2
		return 1;  // if state1 is "greater than" state2
			   // where "less/greater" are any total order
	}

	// create hash table and add initial state
	wHash *hash = wHashCreate(states_compare);
	wState *s = malloc(sizeof(wState));
	s->memory = ...	// put initial state here
	s->hash = ...	// some hash function over memory
	wHashInsert(hash,s);

	// explore all reachable states
	while ((s = wHashPop(hash))
	{
		// find all states t such that s -> t and insert them:
		wHashInsert(hash,t);
	}
*/

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

// Structure representing a program state. Before passing this structure
// to wHashInsert and wHashFind, the fields hash and memory must
// be filled appropriately. The fields next and work are for internal use
// by those functions.

typedef struct wState
{
	struct wState *next;		// linked list in the hash
	struct wState *work;		// linked list in the worklist
	unsigned long hash;		// hash value of state goes here
	void *memory;			// information about the state goes here
} wState;

typedef struct wHash
{
	wState** buckets;
	wState* worklist;
	int min_buckets;
	int num_buckets;
	int num_entries;
	int mask;
	int (*cmp)(wState*,wState*);
} wHash;


/***************************************************************************/
/* Generic hash table:							   */

#define WHASH_MIN 1024  /* initial buckets in new table; must be power of 2 */

/* Create a new hash table. Initially, the table has WHASH_MIN buckets. The
   table will grow automatically if the fill rate exceeds a certain ratio.
   wHashCreate takes a pointer to a user-supplied function as its argument.
   The function is expected to compare two states and to return -1,0,1 if the
   first is considered smaller, equal, larger than the other. This function is
   used by wHashFind and wHashInsert to determine the correct position of
   states, respectively to find whether a state already exists. The table
   intialized by wHashCreate has an empty worklist.*/
extern wHash* wHashCreate (int(*)(wState*,wState*));

/* Insert a state into the table. If the state is already present in 
   the table, returns the pointer to the corresponding entry in the table.
   If the state is indeed new, insert it and return the new state. The state
   is expected to carry its hash value in the 'hash' field of its struct.
   If the state was new, it is also added to the worklist of the hash.  */
extern wState* wHashInsert (wHash*, wState*);

/* Check whether has contains a given state. Returns NULL if not found,
   otherwise a pointer to the copy of the state stored in the hash. */
extern wState* wHashFind (wHash*, wState*);

/* Remove a state from the worklist and return it. The state remains in
   the hash, it is merely removed from the worklist. Returns NULL if worklist
   is empty. */
extern wState* wHashPop (wHash*);


wHash* wHashCreate (int(*cmp)(wState*,wState*))
{
	wHash *table = malloc(sizeof(wHash));

	table->min_buckets = WHASH_MIN;
	table->num_buckets = WHASH_MIN;
	table->num_entries = 0;
	table->mask = WHASH_MIN-1;
	table->buckets = calloc(1,WHASH_MIN * sizeof(wState*));
	table->worklist = NULL;
	table->cmp = cmp;

	return table;
}

wState* wHashInsert (wHash *table, wState *entry)
{
	int i, cmp = 1;
	wState *last_entry = NULL;
	wState *next_entry = table->buckets[entry->hash & table->mask];

	/* determine where the new entry should go */
	while (next_entry)
	{
		cmp = table->cmp(next_entry,entry);
		if (cmp >= 0) break;
		last_entry = next_entry;
		next_entry = next_entry->next;
	}

	/* entry already in hash table, return it */
	if (!cmp) return next_entry;

	/* rehash if needed */
	if (table->num_entries++ >= table->num_buckets * 3/4)
	{
		table->mask = table->num_buckets * 2 - 1;
		table->buckets = realloc(table->buckets,
			table->num_buckets * 2 * sizeof(void*));

		for (i = 0; i < table->num_buckets; i++)
		{
		    wState *l1 = NULL, *l2 = NULL;

		    /* split bucket number i */
		    last_entry = table->buckets[i];
		    while (last_entry)
		    {
			next_entry = last_entry->next;
			if ((last_entry->hash & table->mask)
					== (unsigned long)i)
			{
				last_entry->next = l1;
				l1 = last_entry;
			}
			else
			{
				last_entry->next = l2;
				l2 = last_entry;
			}
			last_entry = next_entry;
		    }

		    /* revert the split buckets */
		    last_entry = NULL;
		    while (l1)
		    {
			next_entry = l1->next;
			l1->next = last_entry;
			last_entry = l1;
			l1 = next_entry;
		    }

		    table->buckets[i] = last_entry;

		    last_entry = NULL;
		    while (l2)
		    {
			next_entry = l2->next;
			l2->next = last_entry;
			last_entry = l2;
			l2 = next_entry;
		    }

		    table->buckets[i + table->num_buckets] = last_entry;
		}

		table->num_buckets *= 2;
		
		last_entry = NULL;
		next_entry = table->buckets[entry->hash & table->mask];

		/* redetermine position of new entry inside its bucket */
		while (next_entry)
		{
		    cmp = table->cmp(next_entry,entry);
		    if (cmp >= 0) break;
		    last_entry = next_entry;
		    next_entry = next_entry->next;
		}
	}

	/* insert new entry into appropriate bucket... */
	i = entry->hash & table->mask;
	if (!last_entry)
	{
		/* ...at beginning of bucket */
		entry->next = table->buckets[i];
		table->buckets[i] = entry;
	}
	else
	{
		/* ...in the middle or at the end */
		entry->next = next_entry;
		last_entry->next = entry;
	}

	/* add new entry to worklist */
	entry->work = table->worklist;
	table->worklist = entry;

	return entry;
}

wState* wHashFind (wHash *table, wState *entry)
{
	wState *next_entry = table->buckets[entry->hash & table->mask];
	
	while (next_entry)
	{
		int cmp = table->cmp(next_entry,entry);
		if (cmp > 0) return NULL;
		if (cmp >= 0) return next_entry;
		next_entry = next_entry->next;
	}

	return NULL;
}

wState* wHashPop (wHash* table)
{
	wState* result = table->worklist;
	if (result) table->worklist = table->worklist->work;
	return result;
}
