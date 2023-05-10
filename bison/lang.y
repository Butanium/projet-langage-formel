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

typedef struct expr	// boolean expression
{
	int type;	// TRUE, FALSE, OR, AND, NOT, 0 (variable)
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

typedef struct spec
{
  int valid;
  expr *expr;
  struct spec *next;
} spec;

/****************************************************************************/
/* All data pertaining to the programme are accessible from these two vars. */

var *program_vars;
stmt *program_stmts;
spec *program_specs;

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
	var *v = program_vars;
	while (v && strcmp(v->name,s)) v = v->next;
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

expr* make_expr (int type, var *var, expr *left, expr *right)
{
	expr *e = malloc(sizeof(expr));
	e->type = type;
	e->var = var;
	e->left = left;
	e->right = right;
	return e;
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
  spec *sp;
}

%type <v> declist
%type <l> varlist
%type <e> expr
%type <s> stmt assign
%type <sp> spec

%token BOOL WHILE DO OD ASSIGN IF ELSE FI PRINT OR AND XOR EQUAL NOT TRUE FALSE REACH GUARD ARROW BREAK
%token <i> IDENT

%left ';'
%left OR XOR
%left AND
%right NOT EQUAL

%%

prog	: bools stmt	{ program_stmts = $2; }

bools	: BOOL declist ';'	{ program_vars = $2; }

declist	: IDENT			{ $$ = make_ident($1); }
	| declist ',' IDENT	{ ($$ = make_ident($3))->next = $1; }

stmt	: assign
	| stmt ';' stmt	
		{ $$ = make_stmt(';',NULL,NULL,$1,$3,NULL); }
	| WHILE expr DO stmt OD
		{ $$ = make_stmt(WHILE,NULL,$2,$4,NULL,NULL); }
	| IF expr THEN stmt ELSE stmt FI
		{ $$ = make_stmt(IF,NULL,$2,$4,$6,NULL); }
	| IF expr THEN stmt FI
		{ $$ = make_stmt(IF,NULL,$2,$4,NULL,NULL); }
	| PRINT varlist
		{ $$ = make_stmt(PRINT,NULL,NULL,NULL,NULL,$2); }
  | REACH expr
    { $$ = make_stmt(REACH,NULL,$2,NULL,NULL,NULL); }
/* (int type, var *var, expr *expr,
			stmt *left, stmt *right, varlist *list)*/
guardlist : 
	| GUARD expr ARROW stmt guardlist
		{ $$ = make_stmt(GUARD,NULL, $2, $4, $5, NULL); }
	| GUARD expr ARROW stmt
		{ $$ = make_stmt(GUARD,NULL, $2, $4, NULL, NULL); }

assign	: IDENT ASSIGN expr
		{ $$ = make_stmt(ASSIGN,find_ident($1),$3,NULL,NULL,NULL); }

varlist	: IDENT			{ $$ = make_varlist($1); }
	| varlist ',' IDENT	{ ($$ = make_varlist($3))->next = $1; }

expr	: IDENT		{ $$ = make_expr(0,find_ident($1),NULL,NULL); }
	| expr XOR expr	{ $$ = make_expr(XOR,NULL,$1,$3); }
	| expr OR expr	{ $$ = make_expr(OR,NULL,$1,$3); }
	| expr AND expr	{ $$ = make_expr(AND,NULL,$1,$3); }
	| expr EQUAL expr {$$ = make_expr(EQUAL, NULL, $1, $3);}
	| NOT expr	{ $$ = make_expr(NOT,NULL,$2,NULL); }
	| TRUE		{ $$ = make_expr(TRUE,NULL,NULL,NULL); }
	| FALSE		{ $$ = make_expr(FALSE,NULL,NULL,NULL); }
	| '(' expr ')'	{ $$ = $2; }
	| ELSE { $$ = make_expr(ELSE, NULL, NULL, NULL); }

spec : { $$ = NULL; }
  | REACH expr spec { $$ = $2; $$->next = $3; }

%%

#include "langlex.c"

/****************************************************************************/
/* programme interpreter      :                                             */

int eval (expr *e)
{
	switch (e->type)
	{
		case TRUE: return 1;
		case FALSE: return 0;
		case XOR: return eval(e->left) ^ eval(e->right);
		case OR: return eval(e->left) || eval(e->right);
		case AND: return eval(e->left) && eval(e->right);
		case EQUAL: return eval(e->left) == eval(e->right);
		case NOT: return !eval(e->left);
		case 0: return e->var->value;
	}
}

void print_vars (varlist *l)
{
	if (!l) return;
	print_vars(l->next);
	printf("%s = %c  ", l->var->name, l->var->value? 'T' : 'F');
}

void execute (stmt *s)
{
	switch(s->type)
	{
		case ASSIGN:
			s->var->value = eval(s->expr);
			break;
		case ';':
			execute(s->left);
			execute(s->right);
			break;
		case WHILE:
			while (eval(s->expr)) execute(s->left);
			break;
		case IF:
		// todo : refactor with guard list.
		// Idea: if guards is fullfilled draw a random number.
		// If another guard is fullfilled, it is executed only 
		// if it's random number is greater
			if (eval(s->expr)) execute(s->left);
			else if (s->right) execute(s->right);
			break;
		case PRINT: 
			print_vars(s->list);
			puts("");
			break;

	}
}

/****************************************************************************/

int main (int argc, char **argv)
{
	if (argc <= 1) { yyerror("no file specified"); exit(1); }
	yyin = fopen(argv[1],"r");
  if (yyparse()) exit(1);

  hash = wHashCreate(xcrc32)

	execute(program_stmts);
}
