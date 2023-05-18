#include "hash.c"
#include "crc32.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "memory.h"
/***************************************************************************/
/* Data structures for storing a programme.                                */

typedef struct varlist // a variable list
{
    char *name;
    int index;
    struct varlist *next;
} varlist;

typedef struct proclist
{
    struct proc *proc;
    struct proclist *next;
} proclist;

typedef struct speclist
{
    int valid;
    expr *expr;
    struct speclist *next;
} speclist;

/****************************************************************************/
/* All data pertaining to the programme are accessible from these two vars. */
int *proc_count;
int *vars_count;
varlist *global_vars_names;
varlist *current_vars_names;
proclist *program_procs = NULL; // liste de tous les processus
speclist *program_specs;        // Liste de toutes les specifications
wHash *hash;
/****************************************************************************/
/* Functions for setting up data structures at parse time.                 */
int find_ident(char *s)
{
    varlist *v = current_vars_names;
    while (v && strcmp(v->name, s))
        v = v->next;
    if (!v)
    {
        v = global_vars_names;
        while (v && strcmp(v->name, s))
            v = v->next;
    }
    if (!v)
    {
        yyerror("undeclared variable");
        exit(1);
    }
    return v->index;
}

varlist *add_var(char *s, varlist *vars)
{
    varlist *v = malloc(sizeof(varlist));
    v->name = s;
    v->index = vars_count;
    vars_count++;
    v->next = vars;
}

proclist *add_proc(stmt *proc)
{
    proclist *p = malloc(sizeof(proclist));
    proc_count++;
    current_vars_names = NULL;
    p->proc = proc;
    p->next = program_procs;
    program_procs = p;
}

speclist *make_speclist(expr *exp, speclist *next)
{
    speclist *s = malloc(sizeof(speclist));
    s->valid = 0;
    s->expr = exp;
    s->next = next;
    return s;
}

expr *make_expr(int type, int var, expr *left, expr *right)
{
    expr *e = malloc(sizeof(expr));
    e->type = type;
    e->var = var;
    e->left = left;
    e->right = right;
    return e;
}

stmt *make_stmt(int type, int var, expr *expr,
                stmt *left, stmt *right)
{
    stmt *s = malloc(sizeof(stmt));
    s->type = type;
    s->var = var;
    s->expr = expr;
    s->left = left;
    s->right = right;
    return s;
}
struct el
{
    int value;
    stmt *stmt;
};

program_state make_init_state()
{
    program_state state = calloc(*vars_count + *proc_count, sizeof(struct el));
    proclist *p = program_procs;
    for (int i = *vars_count; i < *vars_count + *proc_count; i++)
    {
        state[i].stmt = p->proc;
        p = p->next;
    }
    return state;
}

int get_val(program_state state, int var)
{
    return state[var].value;
}

program_state set_val(program_state state, int var, int val)
{
    program_state new_state = malloc(sizeof(struct el) * (*vars_count + *proc_count));
    memcpy(new_state, state, sizeof(struct el) * (*vars_count + *proc_count));
    new_state[var].value = val;
    return new_state;
}

stmt *get_stmt(program_state state, int proc)
{
    return state[*vars_count + proc].stmt;
}

program_state set_stmt(program_state state, int proc, stmt *stmt)
{
    program_state new_state = malloc(sizeof(struct el) * (*vars_count + *proc_count));
    memcpy(new_state, state, sizeof(struct el) * (*vars_count + *proc_count));
    new_state[*vars_count + proc].stmt = stmt;
    return new_state;
}

/****************************************************************************/
/* hash table for states      :                                            */
wState *make_wstate(program_state state)
{
    wState *wstate = malloc(sizeof(struct wState));
    wstate->memory = state;
    wstate->hash = xcrc32((unsigned char *)state, sizeof(struct el) * (*vars_count + *proc_count), 0xffffffff);
    return wstate;
}

int cmp_wstate(wState *state1, wState *state2)
{
    return memcmp(state1->memory, state2->memory, sizeof(struct el) * (*vars_count + *proc_count));
}

void valid_specs()
{
    speclist *s = program_specs;
    while (s != NULL)
    {
        s->valid = s->valid || eval(s->expr);
        s = s->next;
    }
}

int save_state(program_state state)
{
    wState *wstate = make_wstate(state);
    if (wHashFind(hash, wstate) != NULL)
        return 0;

    wHashInsert(hash, wstate);
    valid_specs();

    return 1;
}
