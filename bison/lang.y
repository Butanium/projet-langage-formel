%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "hash.c"
#include "memory.h"
int yylex();

void yyerror(char *s)
{
	fflush(stdout);
	fprintf(stderr, "%s\n", s);
}

%}

/****************************************************************************/

/* types used by terminals and non-terminals */

%union {
	char *i;
	expr *e;
	stmt *s;
	int n;
}

%type <e> expr
%type <s> stmt assign guardlist

%token DO OD ASSIGN IF ELSE FI PRINT OR AND EQUAL NOT REACH GUARD ARROW BREAK SKIP PROC END ADD MUL SUB VAR GT LT
%token <i> IDENT
%token <n> INT

%left ';'
%left OR XOR
%left AND
%left MUL
%left ADD SUB
%right NOT EQUAL

%%

prog	: global_vars proclist	speclist 
proc : PROC IDENT local_vars stmt END { add_proc($4);}
proclist:  { make_init_state();}
	| proc proclist 

local_vars: 
| VAR declist ';' 

global_vars	: {global_vars_names = current_vars_names; current_vars_names = NULL;}
	| VAR declist ';' global_vars

declist	: IDENT			{ add_var($1);}
	| declist ',' IDENT	{ add_var($3);}

stmt	: assign
	| stmt ';' stmt	
		{ $$ = make_stmt(';',-1,NULL,$1,$3); }
	| DO guardlist OD
		{ $$ = make_stmt(DO,-1, NULL,$2,NULL); }
	| IF guardlist FI { $$ = make_stmt(IF,-1,NULL,$2,NULL); }
  | REACH expr
    { $$ = make_stmt(REACH,-1,$2,NULL,NULL); }
/* (int type, var *var, expr *expr,
			stmt *left, stmt *right, )*/
	| SKIP { $$ = make_stmt(SKIP, -1, NULL, NULL, NULL); }
	| BREAK { $$ = make_stmt(BREAK, -1, NULL, NULL, NULL); }

guardlist : 
	 GUARD expr ARROW stmt guardlist
		{ $$ = make_stmt(GUARD,-1, $2, $4, $5); }
	| GUARD expr ARROW stmt
		{ $$ = make_stmt(GUARD,-1, $2, $4, NULL); }

assign	: IDENT ASSIGN expr
		{ $$ = make_stmt(ASSIGN, find_ident($1),$3,NULL,NULL); }


expr	: IDENT		{ $$ = make_expr(0,find_ident($1),NULL,NULL); }
	| expr XOR expr	{ $$ = make_expr(XOR,-1,$1,$3); }
	| expr OR expr	{ $$ = make_expr(OR,-1,$1,$3); }
	| expr AND expr	{ $$ = make_expr(AND,-1,$1,$3); }
	| expr EQUAL expr {$$ = make_expr(EQUAL, -1, $1, $3);}
	| NOT expr	{ $$ = make_expr(NOT,-1,$2,NULL); }
	| '(' expr ')'	{ $$ = $2; }
	| ELSE { $$ = make_expr(ELSE, -1, NULL, NULL); }
  | expr ADD expr { $$ = make_expr(ADD, -1, $1, $3); }
	| expr SUB expr { $$ = make_expr(SUB, -1, $1, $3); }
	| expr MUL expr { $$ = make_expr(MUL, -1, $1, $3); }
	| expr GT expr { $$ = make_expr(GT, -1, $1, $3); }
	| expr LT expr { $$ = make_expr(LT, -1, $1, $3); }
	| INT {$$ = make_expr(INT, $1, NULL, NULL); printf("int %d\n", $1);}

speclist : 
  | REACH expr speclist { make_speclist($2); }

%%

#include "langlex.c"

/****************************************************************************/
/* programme interpreter      :                                             */

int eval(program_state state, expr *e)
{
    switch (e->type)
    {
    case OR:
        return eval(state, e->left) || eval(state, e->right);
    case AND:
        return eval(state, e->left) && eval(state, e->right);
    case EQUAL:
        return eval(state, e->left) == eval(state, e->right);
    case NOT:
        return !eval(state, e->left);
    case ADD:
        return eval(state, e->left) + eval(state, e->right);
    case SUB:
        return eval(state, e->left) - eval(state, e->right);
    case MUL:
        return eval(state, e->left) * eval(state, e->right);
    case ELSE:
        return 1; // todo: implement
    case INT:
        return get_val(state, e->var);
    case 0:
        return get_val(state, e->var);
    }
}

typedef struct stack
{
    stmt *s;
    struct stack *next;
} stack;

typedef struct do_stack
{
    stmt *break_s;
    stack *guard_s;
    struct do_stack *next;
} do_stack;


void valid_specs(program_state state)
{
    speclist *s = program_specs;
    while (s != NULL)
    {
        s->valid = s->valid || eval(state, s->expr);
        s = s->next;
    }
}

int save_state(program_state state)
{
    wState *wstate = make_wstate(state);
    if (wHashFind(hash, wstate) != NULL)
        return 0;

    wHashInsert(hash, wstate);
    valid_specs(state);

    return 1;
}

program_state *exec(program_state state, stmt *next_s, do_stack **current_stack)
{
    if (!save_state(state))
        return NULL;

    program_state *ret_val = malloc(proc_count * sizeof(program_state));

    for (int proc = 0; proc < proc_count; proc++)
    {
        stmt *s = get_stmt(state, proc);
        switch (s->type)
        {
        case ASSIGN:{
            program_state new_state_assign = set_val(state, s->var, eval(state, s->expr));
            ret_val[proc] = new_state_assign;
        }
        case ';':{
            program_state left_state = set_stmt(state, proc, s->left);
            program_state *middle_state = exec(left_state, s->right, current_stack);
            program_state right_state = set_stmt(middle_state[proc], proc, s->right);
            ret_val[proc] = exec(right_state, next_s, current_stack)[proc];
        }
        case DO:{
            struct stack *new_stack_do = malloc(proc_count * sizeof(struct stack));
            new_stack_do->s = s;
            new_stack_do->next = NULL;

            do_stack *new_do_s_do = malloc(proc_count * sizeof(struct do_stack)); //{next_s, new_stack, new_do_s[proc]};
            new_do_s_do->break_s = next_s;
            new_do_s_do->guard_s = new_stack_do;
            new_do_s_do->next = current_stack[proc];

            current_stack[proc] = new_do_s_do;

            ret_val[proc] = exec(state, next_s, current_stack)[proc];
        }
        case IF:{
            program_state new_state_if = set_stmt(state, proc, s->left);
            stack *new_if_s_if = malloc(sizeof(struct stack));
            new_if_s_if->s = next_s;
            new_if_s_if->next = current_stack[proc]->guard_s;

            current_stack[proc]->guard_s = new_if_s_if;

            ret_val[proc] = exec(new_state_if, next_s, current_stack)[proc];
        }
        case PRINT:{
            ret_val[proc] = state;
        }
        case SKIP:{
            ret_val[proc] = state;
        }
        case BREAK:{
            program_state new_state_break = set_stmt(state, proc, current_stack[proc]->break_s);
            do_stack **new_do_s_break = malloc(proc_count * sizeof(struct do_stack *));
            memcpy(new_do_s_break, current_stack, proc_count * sizeof(struct do_stack *));

            new_do_s_break[proc] = new_do_s_break[proc]->next;

            ret_val[proc] = exec(new_state_break, next_s, new_do_s_break)[proc];
        }
        case GUARD:{
            if (eval(state, s->expr))
            {
                program_state new_state_guard = set_stmt(state, proc, s->left);
                program_state guard_state_guard = exec(new_state_guard, next_s, current_stack)[proc];
                program_state next_state_guard = set_stmt(guard_state_guard, proc, current_stack[proc]->guard_s->s);

                do_stack **new_do_s_guard = malloc(proc_count * sizeof(struct do_stack *));
                memcpy(new_do_s_guard, current_stack, proc_count * sizeof(struct do_stack *));

                new_do_s_guard[proc]->guard_s = current_stack[proc]->guard_s->next;

                exec(next_state_guard, next_s, new_do_s_guard);
            }

            if (s->right != NULL)
            {
                program_state new_state_guard = set_stmt(state, proc, s->right);
                exec(new_state_guard, next_s, current_stack);
            }
            ret_val[proc] = NULL;
        }
        }
    }
}

/****************************************************************************/

int main (int argc, char **argv)
{
	if (argc <= 1) { yyerror("no file specified"); exit(1); }
	yyin = fopen(argv[1],"r");

    hash = wHashCreate(cmp_wstate);

	if (!yyparse()) printf("parsing successful\n");
	else exit(1);
	// exec();
}
