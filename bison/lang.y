%{

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "hash.c"
#include "crc32.c"

int yylex();

void yyerror(char *s)
{
	fflush(stdout);
	fprintf(stderr, "%s\n", s);
}

/***************************************************************************/
/* Data structures for storing a programme.                                */

typedef struct var	// a variable
{
	char *name;
	int value;
	struct var *next;
} var;

typedef struct varlist	// variable reference (used for print statement)
{
	struct var *var;
	struct varlist *next;
} varlist;

typedef struct proclist
{
	struct stmt *body;
	struct var *local_vars;
	struct proclist *next;
	char *name;
} proclist;

typedef struct expr	// boolean expression
{
	int type;	// INT, OR, AND, NOT, 0 (variable)
	var *var;
	struct expr *left, *right;
} expr;

typedef struct stmt	// command
{
	int type;	// ASSIGN, ';', WHILE, PRINT
	var *var;
	expr *expr;
	struct stmt *left, *right;
	varlist *list;
} stmt;

typedef struct speclist
{
  int valid;
  expr *expr;
  struct speclist *next;
} speclist;

typedef struct stmtlist
{
  stmt *stmt;
  struct stmtlist *next;
} stmtlist;

typedef struct program_state
{
  var global_vars;
  var local_vars;
  stmtlist *stmts; // one statement per process
} program_state;

/****************************************************************************/
/* All data pertaining to the programme are accessible from these two vars. */

var *global_vars;
var *current_vars;
proclist *program_procs = NULL;
speclist *program_specs;

wHash *hash;


/****************************************************************************/
/* Functions for setting up data structures at parse time.                 */

var* make_ident (char *s)
{
	var *v = malloc(sizeof(var));
	v->name = s;
	v->value = 0;	// make variable false initially
	v->next = NULL;
	return v;
}


var* find_ident (char *s)
{
	var *v = current_vars;
	while (v && strcmp(v->name,s)) v = v->next;
	if (!v) {
		v = global_vars;
		while (v && strcmp(v->name,s)) v = v->next;
	}
	if (!v) { yyerror("undeclared variable"); exit(1); }
	return v;
}

varlist* make_varlist (char *s)
{
	var *v = find_ident(s);
	varlist *l = malloc(sizeof(varlist));
	l->var = v;
	l->next = NULL;
	return l;
}

proclist* make_proclist (stmt *s, char *name)
{
	proclist *p = malloc(sizeof(proclist));
	p->body = s;
	p->name = name;
	p->local_vars = current_vars;
	current_vars = NULL;
	p->next = program_procs;
	program_procs = p;
}

speclist* make_speclist (expr *exp, speclist* next)
{
  speclist *s = malloc(sizeof(speclist));
  s->valid = 0;
  s->expr = exp;
  s->next = next;
  return s;
}

expr* make_expr (int type, var *var, expr *left, expr *right)
{
	expr *e = malloc(sizeof(expr));
	e->type = type;
	e->var = var;
	e->left = left;
	e->right = right;
	return e;
}

expr* make_const(int type, int n)
{
	var *v = malloc(sizeof(var));
	v->name = NULL;
	v->value = n;
	v->next = NULL;
	return make_expr(type, v, NULL, NULL);
}

stmt* make_stmt (int type, var *var, expr *expr,
			stmt *left, stmt *right, varlist *list)
{
	stmt *s = malloc(sizeof(stmt));
	s->type = type;
	s->var = var;
	s->expr = expr;
	s->left = left;
	s->right = right;
	s->list = list;
	return s;
}


%}

/****************************************************************************/

/* types used by terminals and non-terminals */

%union {
	char *i;
	var *v;
	varlist *l;
	expr *e;
	stmt *s;
	int n;
  speclist *spec;
}

%type <v> declist
%type <l> varlist
%type <e> expr
%type <s> stmt assign guardlist
%type <spec> speclist

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

prog	: global_vars  proclist	speclist { program_specs = $3; }
proc : PROC IDENT local_vars stmt END { make_proclist($4, $2);}
proclist: 
	 proc proclist 
	| proc

local_vars: 
| VAR declist ';' { current_vars = $2; }

global_vars	: 
	VAR declist ';'	{ global_vars = $2; }
	| VAR declist ';' global_vars
		{ global_vars->next = $2; }

declist	: IDENT			{ $$ = make_ident($1); }
	| declist ',' IDENT	{ ($$ = make_ident($3))->next = $1; }

stmt	: assign
	// TODO: allow local variables
	| stmt ';' stmt	
		{ $$ = make_stmt(';',NULL,NULL,$1,$3,NULL); }
	| DO guardlist OD
		{ $$ = make_stmt(DO,NULL, NULL,$2,NULL,NULL); }
	| IF guardlist FI { $$ = make_stmt(IF,NULL,NULL,$2,NULL,NULL); }
	| PRINT varlist
		{ $$ = make_stmt(PRINT,NULL,NULL,NULL,NULL,$2); }
  | REACH expr
    { $$ = make_stmt(REACH,NULL,$2,NULL,NULL,NULL); }
/* (int type, var *var, expr *expr,
			stmt *left, stmt *right, varlist *list)*/
	| SKIP { $$ = make_stmt(SKIP, NULL, NULL, NULL, NULL, NULL); }
	| BREAK { $$ = make_stmt(BREAK, NULL, NULL, NULL, NULL, NULL); }

guardlist : 
	 GUARD expr ARROW stmt guardlist
		{ $$ = make_stmt(GUARD,NULL, $2, $4, $5, NULL); }
	| GUARD expr ARROW stmt
		{ $$ = make_stmt(GUARD,NULL, $2, $4, NULL, NULL); }

assign	: IDENT ASSIGN expr
		{ $$ = make_stmt(ASSIGN, find_ident($1),$3,NULL,NULL,NULL); }

varlist	: IDENT			{ $$ = make_varlist($1); }
	| varlist ',' IDENT	{ ($$ = make_varlist($3))->next = $1; }

expr	: IDENT		{ $$ = make_expr(0,find_ident($1),NULL,NULL); }
	| expr XOR expr	{ $$ = make_expr(XOR,NULL,$1,$3); }
	| expr OR expr	{ $$ = make_expr(OR,NULL,$1,$3); }
	| expr AND expr	{ $$ = make_expr(AND,NULL,$1,$3); }
	| expr EQUAL expr {$$ = make_expr(EQUAL, NULL, $1, $3);}
	| NOT expr	{ $$ = make_expr(NOT,NULL,$2,NULL); }
	| '(' expr ')'	{ $$ = $2; }
	| ELSE { $$ = make_expr(ELSE, NULL, NULL, NULL); }
  | expr ADD expr { $$ = make_expr(ADD, NULL, $1, $3); }
	| expr SUB expr { $$ = make_expr(SUB, NULL, $1, $3); }
	| expr MUL expr { $$ = make_expr(MUL, NULL, $1, $3); }
	| expr GT expr { $$ = make_expr(GT, NULL, $1, $3); }
	| expr LT expr { $$ = make_expr(LT, NULL, $1, $3); }
	| INT {$$ = make_const(INT, $1);}

speclist : { $$ = NULL; }
  | REACH expr speclist { $$ = make_speclist($2, $3); }

%%

#include "langlex.c"

/****************************************************************************/
/* programme interpreter      :                                             */

int eval (expr *e)
{
	switch (e->type)
	{
		case OR: return eval(e->left) || eval(e->right);
		case AND: return eval(e->left) && eval(e->right);
		case EQUAL: return eval(e->left) == eval(e->right);
		case NOT: return !eval(e->left);
		case ADD: return eval(e->left) + eval(e->right);
		case SUB: return eval(e->left) - eval(e->right);
		case MUL: return eval(e->left) * eval(e->right);
		case ELSE: return 1; // todo: implement
		case INT: return e->var->value;
		case 0: return e->var->value;
	}
}

void print_vars (varlist *l)
{
	if (!l) return;
	print_vars(l->next);
	printf("%s = %d  ", l->var->name, l->var->value);
}


int execute (stmt *s)
{
	switch(s->type)
	{
		case ASSIGN:
			s->var->value = eval(s->expr);
			return 0;
		case ';':
			if (execute(s->left)) return 1;
			return execute(s->right);
		case DO:
			while (execute(s->left) == 0);
			return 0;
		case IF:
			execute(s->left);
		case PRINT: 
			print_vars(s->list);
			puts("");
			return 0;
		case SKIP:
			return 0;
		case BREAK:
			return 1;
		case GUARD:
			if (eval(s->expr)) {
				if (execute(s->left)) return 1;
			} else {
				return execute(s->right);
			}
	}
}


/****************************************************************************/
/* specs checker      :                                                     */


void valid_specs()
{
  speclist *s = program_specs;
  while (s != NULL)
  {
    s->valid = s->valid || eval(s->expr);
    s = s->next;
  }
}


/****************************************************************************/
/* hash table for states      :                                            */

program_state *make_pstate(var global_vars, var local_vars, stmtlist *stmts)
{
  program_state *state = malloc(sizeof(struct program_state));
  state->global_vars = global_vars;
  state->local_vars = local_vars;
  memcpy(state->stmts, stmts, sizeof(struct stmtlist));
  return state;
}

wState *make_wstate(program_state *state)
{
  wState *wstate = malloc(sizeof(struct wState));
  wstate->memory = state;
  wstate->hash = xcrc32(state, sizeof(struct program_state), 0xffffffff);
  return wstate;
}

int save_current_state(stmtlist *stmts)
{
  program_state *state = make_pstate(*global_vars, *current_vars, stmts);
  wState *wstate = make_wstate(state);

  if (wHashFind(hash, wstate) != NULL) return 0; 

  wHashInsert(hash, wstate);
  valid_specs();

  return 1;
}


/****************************************************************************/

int main (int argc, char **argv)
{
	if (argc <= 1) { yyerror("no file specified"); exit(1); }
	yyin = fopen(argv[1],"r");

  //hash = wHashCreate(xcrc32)

	if (!yyparse()) printf("parsing successful\n");
	else exit(1);
	// execute(program_stmts);
}
