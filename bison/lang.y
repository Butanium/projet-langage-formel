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
typedef struct expr // boolean expression
{
    int type; // INT, OR, AND, NOT, 0 (variable)
    int var; // VAR index or INT constant
    struct expr *left, *right;
} expr;

typedef struct stmt // command
{
    int type; // ASSIGN, ';', DO, IF, GUARD
    int var;
    expr *expr;
    struct stmt *left, *right;
} stmt;



typedef struct speclist
{
    int valid;
    expr *expr;
    struct speclist *next;
} speclist;

struct varlist;
struct speclist;
typedef struct el *program_state;
typedef struct varlist // a variable list
{
    char *name;
    int index;
    struct varlist *next;
} varlist;
typedef struct proclist
{
    struct stmt *proc;
    struct proclist *next;
} proclist;

/****************************************************************************/
/* All data pertaining to the programme are accessible from these two vars. */
int proc_count;
program_state init_state;
int vars_count;
varlist *global_vars_names;
varlist *current_vars_names = NULL;
proclist *program_procs = NULL; // liste de tous les processus
speclist *program_specs = NULL; // Liste de toutes les specifications
wHash *hash;

/****************************************************************************/
/* Functions for setting up data structures at parse time.                 */
int find_ident(char *s)
{
    varlist *v = current_vars_names;
    while (v && strcmp(v->name, s))
    {
        v = v->next;
    }
    if (!v)
    {
        v = global_vars_names;
        while (v && strcmp(v->name, s))
        {
            v = v->next;
        }
    }
    if (!v)
    {
        yyerror("undeclared variable");
        exit(1);
    }
    return v->index;
}

void add_var(char *s)
{
    varlist *v = malloc(sizeof(varlist));
    v->name = s;
    v->index = vars_count;
    vars_count++;
    v->next = current_vars_names;
    current_vars_names = v;
}

void add_proc(stmt *proc)
{
    proclist *p = malloc(sizeof(proclist));
    proc_count++;
    current_vars_names = NULL;
    p->proc = proc;
    p->next = program_procs;
    program_procs = p;
}

void make_speclist(expr *exp)
{
    speclist *s = malloc(sizeof(speclist));
    s->valid = 0;
    s->expr = exp;
    s->next = program_specs;
    program_specs = s;
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

// For DO and IF statements, we need to add a SKIP statement at the end
// to make sure after to have a statement to execute after a break / a guard
stmt *make_stmt_end(int type, int var, expr *expr,
                    stmt *left, stmt *right, int end_type)
{
    stmt *s = make_stmt(type, var, expr, left, right);
    stmt *end = make_stmt(end_type, -1, NULL, NULL, NULL);
    return make_stmt(';', -1, NULL, s, end);
}
struct el
{
    int value;
    stmt *stmt;
};

void make_init_state()
{
    program_state state = calloc(vars_count + proc_count, sizeof(struct el));
    proclist *p = program_procs;
    for (int i = vars_count; i < vars_count + proc_count; i++)
    {
        state[i].stmt = p->proc;
        p = p->next;
    }
    init_state = state;
}
%}

/****************************************************************************/

/* types used by terminals and non-terminals */

%union{
    char *i;
    expr *e;
    stmt *s;
    int n;
}

%type<e> expr 
%type<s> stmt assign guardlist
%token DO OD ASSIGN IF ELSE FI PRINT OR AND EQUAL NOT REACH GUARD ARROW BREAK SKIP PROC END ADD MUL SUB VAR GT LT END_DO
%token<i> IDENT 
%token<n> INT
%left ';' %left OR XOR %left AND %left MUL %left ADD SUB %right NOT EQUAL
%%

prog : global_vars {global_vars_names = current_vars_names; current_vars_names = NULL;}
        proclist speclist
proc : PROC IDENT local_vars stmt END { add_proc($4); }
proclist: { make_init_state(); }
    | proc proclist

local_vars : 
    |VAR declist ';'

global_vars : 
    |VAR declist ';' global_vars

declist : IDENT {add_var($1);}
    | declist ',' IDENT { add_var($3); }

stmt : assign 
| stmt ';' stmt {$$ = make_stmt(';', -1, NULL, $1, $3);}
| DO guardlist OD {$$ = make_stmt_end(DO, -1, NULL, $2, NULL, END_DO);}
| IF guardlist FI { $$ = make_stmt_end(IF, -1, NULL, $2, NULL, SKIP); }
| REACH expr {$$ = make_stmt(REACH, -1, $2, NULL, NULL);}
/* (int type, var *var, expr *expr,
            stmt *left, stmt *right, )*/
| SKIP { $$ = make_stmt(SKIP, -1, NULL, NULL, NULL); }
| BREAK { $$ = make_stmt(BREAK, -1, NULL, NULL, NULL); }

guardlist : GUARD expr ARROW stmt guardlist {$$ = make_stmt(GUARD, -1, $2, $4, $5);}
| GUARD expr ARROW stmt {$$ = make_stmt(GUARD, -1, $2, $4, NULL);}

assign : IDENT ASSIGN expr {$$ = make_stmt(ASSIGN, find_ident($1), $3, NULL, NULL);}

expr : IDENT { $$ = make_expr(0, find_ident($1), NULL, NULL); }
| expr XOR expr { $$ = make_expr(XOR, -1, $1, $3); }
| expr OR expr { $$ = make_expr(OR, -1, $1, $3); }
| expr AND expr { $$ = make_expr(AND, -1, $1, $3); }
| expr EQUAL expr { $$ = make_expr(EQUAL, -1, $1, $3); }
| NOT expr { $$ = make_expr(NOT, -1, $2, NULL); }
| '(' expr ')' { $$ = $2; }
| ELSE { $$ = make_expr(ELSE, -1, NULL, NULL); }
| expr ADD expr { $$ = make_expr(ADD, -1, $1, $3); }
| expr SUB expr { $$ = make_expr(SUB, -1, $1, $3); }
| expr MUL expr { $$ = make_expr(MUL, -1, $1, $3); }
| expr GT expr { $$ = make_expr(GT, -1, $1, $3); }
| expr LT expr { $$ = make_expr(LT, -1, $1, $3); }
| INT { $$ = make_expr(INT, $1, NULL, NULL); }

speclist : | REACH expr speclist { make_speclist($2); }

%%

#include "langlex.c"



int get_val(program_state state, int var)
{
    return state[var].value;
}

program_state set_val(program_state state, int var, int val)
{
    program_state new_state = malloc(sizeof(struct el) * (vars_count + proc_count));
    memcpy(new_state, state, sizeof(struct el) * (vars_count + proc_count));
    new_state[var].value = val;
    return new_state;
}

stmt *get_stmt(program_state state, int proc)
{
    return state[vars_count + proc].stmt;
}

program_state set_stmt(program_state state, int proc, stmt *stmt)
{
    program_state new_state = malloc(sizeof(struct el) * (vars_count + proc_count));
    memcpy(new_state, state, sizeof(struct el) * (vars_count + proc_count));
    new_state[vars_count + proc].stmt = stmt;
    return new_state;
}

/****************************************************************************/
/* hash table for states      :                                            */
wState *make_wstate(program_state state)
{
    wState *wstate = malloc(sizeof(struct wState));
    wstate->memory = state;
    wstate->hash = xcrc32((unsigned char *)state, sizeof(struct el) * (vars_count + proc_count), 0xffffffff);
    return wstate;
}

int cmp_wstate(wState *state1, wState *state2)
{
    return memcmp(state1->memory, state2->memory, sizeof(struct el) * (vars_count + proc_count));
}

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
        return e->var;
    case 0:
        return get_val(state, e->var);
    }
}

void valid_specs(program_state state)
{
    speclist *s = program_specs;
    while (s != NULL)
    {
        if (!s->valid && eval(state, s->expr)) { printf("validing spec : %d\n", eval(state, s->expr)); }
        s->valid = s->valid || eval(state, s->expr);
        s = s->next;
    }
}

int save_state(program_state state)
{
    wState *wstate = make_wstate(state);
    if (wHashFind(hash, wstate) != NULL) return 0;

    wHashInsert(hash, wstate);
    valid_specs(state);

    return 1;
}
int execcount;



// Pile pour les environnements DO
typedef struct do_stack
{
  stmt *break_s;
  struct do_stack *next;
} do_stack;

//Concaténation de deux stmt
stmt *concat_stmt(stmt *s1, stmt *s2)
{
  if (s1 == NULL && s2 == NULL) return NULL;
  if (s1 == NULL) return s2;
  if (s2 == NULL) return s1;
  return make_stmt(';', -1, NULL, s1, s2);
}

//Modifie un stmt* dans un tableau
stmt **mod_stmts(stmt **arr, int proc, stmt *s)
{
  stmt **new_arr = malloc(sizeof(stmt *) * proc_count);
  memcpy(new_arr, arr, sizeof(stmt *) * proc_count);
  new_arr[proc] = s;
  return new_arr;
}

//Modifie un do_stack* dans un tableau
do_stack **mod_stacks(do_stack **arr, int proc, do_stack *s)
{
  do_stack **new_arr = malloc(sizeof(do_stack *) * proc_count);
  memcpy(new_arr, arr, sizeof(do_stack *) * proc_count);
  new_arr[proc] = s;
  return new_arr;
}

// exec(state, nexts, stacks, guard_visited) va parcourir tout les états atteignable non visités depuis state avec comme prochains stmts nexts et comme environnements DO stacks
// guard_visited n'a de sens que dans un guard qui indique si un guard a été visité ou non (pour éviter de boucler et le else)
void exec(program_state state, stmt **nexts, do_stack **stacks)
{
    // Si on l'a déjà visité on ne fait rien
    if (!save_state(state)) return;


    // On essaye d'avancer chaque processus d'une étape
    for (int proc = 0; proc < proc_count; proc++)
    {

        //Le stmt courant du processus
        stmt *current_stmt = get_stmt(state, proc);

        //On regarde ce qu'on a à faire
        switch (current_stmt->type)
        {
          // Si on est dans un assign : on chanqe la valeur et on essaye de continuer
          case ASSIGN:
          {
              //On modifie d'abord la valeur dans l'état
              program_state mod_state = set_val(state, current_stmt->var, eval(state, current_stmt->expr));

              if (nexts[proc] == NULL)
              {
                //Si on a pas de code après, on vérifie l'état et on s'arrête
                save_state(mod_state);
                return;
              }
              else
              {
                //Si on a du code après, on l'exécute
                stmt *next_stmt = nexts[proc];
                stmt **new_nexts = mod_stmts(nexts, proc, NULL);
                program_state next_state = set_stmt(mod_state, proc, next_stmt);
                exec(next_state, new_nexts, stacks);
              }
          }
          break;

          //On est dans une concaténation : on exécute le premier en donnant le second comme suite
          case ';':
          {
              // On récupère l'état
              program_state next_state = set_stmt(state, proc, current_stmt->left);
              stmt **new_nexts = mod_stmts(nexts, proc, concat_stmt(current_stmt->right, nexts[proc]));

              //On execute le reste
              exec(next_state, new_nexts, stacks);
          }
          break;

          //On est dans un DO : on empile un nouvel environnement sur la pile et on execute les guards
          case DO:
          {
              //On créer un nouveau noeud de la pile
              do_stack *new_stack = malloc(sizeof(struct do_stack));

              //Si on break dans le DO, il faut executer ce qui suit le DO
              new_stack->break_s = nexts[proc];
              new_stack->next = stacks[proc];

              do_stack **new_stacks = mod_stacks(stacks, proc, new_stack);

              //Ce qu'il faut faire après un guard : revenir au premier guard
              stmt **new_nexts = mod_stmts(nexts, proc, current_stmt->left);

              //On crée le nouvel état
              program_state new_state = set_stmt(state, proc, current_stmt->left);

              //On reset le guard_visited
              //int *new_guard_visited = malloc(sizeof(int) * proc_count);
              //memcpy(new_guard_visited, guard_visited, sizeof(int) * proc_count);
              //new_guard_visited[proc] = 0;

              //On execute l'état
              exec(new_state, new_nexts, new_stacks);
          }
          break;

          // On est dans un IF : on execute les guards
          case IF:
          {
              //On crée le nouvel état
              program_state new_state = set_stmt(state, proc, current_stmt->left);

              //On reset le guard_visited
              //int *new_guard_visited = malloc(sizeof(int) * proc_count);
              //memcpy(new_guard_visited, guard_visited, sizeof(int) * proc_count);
              //new_guard_visited[proc] = 0;

              //On execute cet état
              exec(new_state, nexts, stacks);
          }
          break;

          // On est dans un PRINT ou dans un SKIP : on continue juste d'exécuter la suite
          // Ajout d'un SKIP_DO ?
          case PRINT:
          case SKIP:
          {
            if (nexts[proc] == NULL) return;

            //On crée le nouvel état
            program_state new_state = set_stmt(state, proc, nexts[proc]);

            stmt **new_nexts = mod_stmts(nexts, proc, NULL);

            //On execute la suite
            exec(new_state, new_nexts, stacks);
          }
          break;

          //On est dans le cas d'un SKIP_DO : on dépile le DO et on execute ce qui suit le DO
          case END_DO:
          {
            if (nexts[proc] == NULL) return;

            //On crée la pile sans la tête
            do_stack **new_stacks = mod_stacks(stacks, proc, stacks[proc]->next);

            //On crée le nouvel état
            program_state new_state = set_stmt(state, proc, nexts[proc]);

            stmt **new_nexts = mod_stmts(nexts, proc, NULL);

            //On execute la suite
            exec(new_state, new_nexts, new_stacks);
          }

          //On est dans le cas d'un BREAK : on execute ce qui suit le DO (le DO est suivi d'un SKIP_DO qui s'occupera de dépiler la do_stack)
          case BREAK:
          {
              //On crée le nouvel état
              program_state new_state = set_stmt(state, proc, stacks[proc]->break_s);

              stmt **new_nexts = mod_stmts(nexts, proc, NULL);

              //On execute la suite
              exec(new_state, new_nexts, stacks);
          }
          break;

          //On est dans le cas d'un GUARD : on regarde si le guard courant est vrai, si oui on l'execute
          //Et on execute les autre guards si il y en a
          case GUARD:
          {
              //int guard_state;
              //On regarde si le guard est valide
              if (eval(state, current_stmt->expr))
              {
                  //guard_state = 1;

                  //Si oui, on crée le nouvel état
                  program_state new_state = set_stmt(state, proc, current_stmt->left);

                  //On execute le guard
                  exec(new_state, nexts, stacks);
              }


              //On regarde si il y a d'autres guards
              if (current_stmt->right != NULL)
              {
                  //On crée le nouvel état
                  program_state new_state = set_stmt(state, proc, current_stmt->right);

                  //int *new_guard_visited = malloc(sizeof(int) * proc_count);
                  //memcpy(new_guard_visited, guard_visited, sizeof(int) * proc_count);
                  //new_guard_visited[proc] = guard_visited[proc] || guard_state;

                  //On execute les guards
                  exec(new_state, nexts, stacks);
              }
          }
          break;
        }
    }
}

/****************************************************************************/

int main(int argc, char **argv)
{
    if (argc <= 1)
    {
        yyerror("no file specified");
        exit(1);
    }
    yyin = fopen(argv[1], "r");

    hash = wHashCreate(cmp_wstate);

    if (!yyparse())
        printf("parsing successful\n");
    else
        exit(1);

    do_stack **stacks = malloc(proc_count * sizeof(do_stack *));
    for (int i = 0; i < proc_count; i++) stacks[i] = NULL;

    stmt **nexts = malloc(proc_count * sizeof(stmt *));
    for (int i = 0; i < proc_count; i++) nexts[i] = NULL;

    //int *guard_visited = malloc(proc_count * sizeof(int));
    //for (int i = 0; i < proc_count; i++) guard_visited[i] = 0;

    exec(init_state, nexts, stacks);

    speclist *specs = program_specs;
    int i = 0;
    if (specs == NULL)
        printf("No specs\n");
    while (specs != NULL)
    {
        i++;
        printf("Spec %d: %d\n", i, specs->valid);
        specs = specs->next;
    }
}
