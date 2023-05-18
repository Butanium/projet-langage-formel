%{

int yylex();

void yyerror(char *s)
{
	fflush(stdout);
	fprintf(stderr, "%s\n", s);
}

program_state init_state;
%}

/****************************************************************************/

/* types used by terminals and non-terminals */

%union {
	char *i;
	expr *e;
	stmt *s;
	int n;
  speclist *spec;
}

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

prog	: global_vars proclist	speclist { program_specs = $3; }
proc : PROC IDENT local_vars stmt END { make_proclist($4, $2);}
proclist:  { init_state = make_init_state();}
	| proc proclist 

local_vars: 
| VAR declist ';' { current_vars = $2; }

global_vars	: 
	| VAR declist ';' global_vars
		{ global_vars->next = $2; }

declist	: IDENT			{ $$ = make_ident($1);}
	| declist ',' IDENT	{ ($$ = make_ident($3))->next = $1; current_vars_count++; }

stmt	: assign
	| stmt ';' stmt	
		{ $$ = make_stmt(';',NULL,NULL,$1,$3); }
	| DO guardlist OD
		{ $$ = make_stmt(DO,NULL, NULL,$2,NULL); }
	| IF guardlist FI { $$ = make_stmt(IF,NULL,NULL,$2,NULL); }
  | REACH expr
    { $$ = make_stmt(REACH,NULL,$2,NULL,NULL,NULL); }
/* (int type, var *var, expr *expr,
			stmt *left, stmt *right, )*/
	| SKIP { $$ = make_stmt(SKIP, NULL, NULL, NULL, NULL); }
	| BREAK { $$ = make_stmt(BREAK, NULL, NULL, NULL, NULL); }

guardlist : 
	 GUARD expr ARROW stmt guardlist
		{ $$ = make_stmt(GUARD,NULL, $2, $4, $5, NULL); }
	| GUARD expr ARROW stmt
		{ $$ = make_stmt(GUARD,NULL, $2, $4, NULL, NULL); }

assign	: IDENT ASSIGN expr
		{ $$ = make_stmt(ASSIGN, find_ident($1),$3,NULL,NULL,NULL); }


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
		case INT: return e->var->value; // const
		case 0: return e->var->value; // ident
	}
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


/****************************************************************************/

int main (int argc, char **argv)
{
	if (argc <= 1) { yyerror("no file specified"); exit(1); }
	yyin = fopen(argv[1],"r");

  hash = wHashCreate(cmp_wstate);

	if (!yyparse()) printf("parsing successful\n");
	else exit(1);
	exec();
}
