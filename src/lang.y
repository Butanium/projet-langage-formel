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

// Une expression (retourne un entier)
typedef struct expr // boolean expression
{
    int type; //  OR AND EQUAL NOT ADD MUL SUB VAR GT LT, 0 (variable)
    int var; // index d'une VAR dans l'env ou une constante INT 
    struct expr *left, *right;
} expr;

// Une instruction du programme
typedef struct stmt // command
{
    int type; // ASSIGN, ';', DO, IF, GUARD, BREAK, SKIP, END_DO
    int var; // L'index de la var pour ASSIGN
    expr *expr; // L'expression pour ASSIGN, la condition pour GUARD, NULL sinon
    struct stmt *left, *right;
} stmt;


// Une liste de spécifications (reach)
typedef struct speclist
{
    int valid; // 0 si la spécification n'est pas encore vérifiée, 1 sinon
    expr *expr; // La spécification à vérifier
    struct speclist *next;
} speclist;

// Un état est l'ensemble des valeurs des variables et des instructions courantes des processeurs.
// Pour pouvoir hasher et comparer en utilisant xcrc32, on a besoin que les variables et les 
// instructions soient stockées dans une mémoire adjacente.
// Afin de stocker les instructions courantes dans une mémoire adjacente aux valeurs des variables,
// on utilise un tableau de "el", une structures qui peut contenir une valeur de variable et une instruction.
struct el
{
    int value;
    stmt *stmt;
};

// Un état est donc un tableau de "el"
typedef struct el *program_state;

// Une liste de variables
typedef struct varlist 
{
    char *name; // le nom de la variable
    int index; // l'index de la variable dans l'environnement
    struct varlist *next;
} varlist;

// Une liste de processeurs
typedef struct proclist
{
    struct stmt *proc; // Le corps du processeur
    struct proclist *next;
} proclist;

/****************************************************************************/
/*               Données qui sont remplies pendant le pars                  */
/****************************************************************************/
int proc_count; // Nombre de processeurs dans le programme
program_state init_state; // L'état initial du programme (variables = 0 et instruction courante des processeur = la première instruction)
int vars_count; // Nombre de variables dans le programme, utilisé pour l'allocation de l'environnement
varlist *global_vars_names; // Liste des variables globales du programme
varlist *current_vars_names = NULL; // List des variables locales du processeur qui est en train d'être parsé
proclist *program_procs = NULL; // Liste de tous les processus
speclist *program_specs = NULL; // Liste de toutes les specifications
wHash *hash;

/****************************************************************************/
/*         Fonctions pour remplir les données pendant le parsing            */
/****************************************************************************/

// Cherche l'index dans l'environement d'une variable.
int find_ident(char *s)
{
    // Recherche dans l'environnement local
    varlist *v = current_vars_names;
    while (v && strcmp(v->name, s))
    {
        v = v->next;
    }
    if (!v)
    {
        // Si ce n'est pas trouvé, recherche dans l'environnement global
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

// Ajoute la variable à l'environnement courant
void add_var(char *s)
{
    varlist *v = malloc(sizeof(varlist));
    v->name = s;
    v->index = vars_count;
    vars_count++;
    v->next = current_vars_names;
    current_vars_names = v;
}

// Ajout un nouveau processeur à la liste des processeurs
void add_proc(stmt *proc)
{
    proclist *p = malloc(sizeof(proclist));
    proc_count++;
    // On réinitialise la liste des variables locales
    current_vars_names = NULL;
    p->proc = proc;
    p->next = program_procs;
    program_procs = p;
}

// Ajout une nouvelle spécification à la liste des spécifications
void make_speclist(expr *exp)
{
    speclist *s = malloc(sizeof(speclist));
    s->valid = 0;
    s->expr = exp;
    s->next = program_specs;
    program_specs = s;
}

// Création d'une expression
expr *make_expr(int type, int var, expr *left, expr *right)
{
    expr *e = malloc(sizeof(expr));
    e->type = type;
    e->var = var;
    e->left = left;
    e->right = right;
    return e;
}

// Création d'une instruction
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

// Pour une instruction S, créer un stmt pour S;end_type avec end_type = END_DO (pour DO) ou SKIP (pour IF)
// C'est pour s'assurer qu'il y ait toujours une instruction à exécuter après un break ou un guard
stmt *make_stmt_end(int type, int var, expr *expr,
                    stmt *left, stmt *right, int end_type)
{
    stmt *s = make_stmt(type, var, expr, left, right);
    stmt *end = make_stmt(end_type, -1, NULL, NULL, NULL);
    return make_stmt(';', -1, NULL, s, end);
}

void make_init_state()
{
    // On alloue un tableau de "el" de taille vars_count + proc_count
    // L'utilisation de calloc permet d'initialiser toutes les valeurs à 0
    program_state state = calloc(vars_count + proc_count, sizeof(struct el));
    proclist *p = program_procs;
    for (int i = vars_count; i < vars_count + proc_count; i++)
    {
        // On stocke les instructions courantes des processeurs dans le tableau
        state[i].stmt = p->proc;
        p = p->next;
    }
    init_state = state;
}
%}

/****************************************************************************/
/*          Types utilisés par les terminaux et les non-terminaux           */
/****************************************************************************/
%union{
    char *i;
    expr *e;
    stmt *s;
    int n;
}

%type<e> expr 
%type<s> stmt assign guardlist
%token DO OD ASSIGN IF ELSE FI OR AND EQUAL NOT REACH GUARD ARROW BREAK SKIP PROC END ADD MUL SUB VAR GT LT END_DO
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

speclist : 
    | REACH expr speclist { make_speclist($2); }

%%

#include "langlex.c"


// Renvoie la valeur de la variable var dans l'état state
int get_val(program_state state, int var)
{
    return state[var].value;
}

// Créer un nouvel état à partir de l'état state en changeant la valeur de la variable var à val
program_state set_val(program_state state, int var, int val)
{
    program_state new_state = malloc(sizeof(struct el) * (vars_count + proc_count));
    memcpy(new_state, state, sizeof(struct el) * (vars_count + proc_count));
    new_state[var].value = val;
    return new_state;
}

// Renvoie l'instruction courante du processeur proc dans l'état state
stmt *get_stmt(program_state state, int proc)
{
    return state[vars_count + proc].stmt;
}

// Créer un nouvel état à partir de l'état state en changeant l'instruction courante du processeur proc à stmt
program_state set_stmt(program_state state, int proc, stmt *stmt)
{
    program_state new_state = malloc(sizeof(struct el) * (vars_count + proc_count));
    memcpy(new_state, state, sizeof(struct el) * (vars_count + proc_count));
    new_state[vars_count + proc].stmt = stmt;
    return new_state;
}

/****************************************************************************/
/*                     Hashtable pour les program_state                     */
/****************************************************************************/

// Créer un élément de la hashtable pour un program_state
wState *make_wstate(program_state state)
{
    wState *wstate = malloc(sizeof(struct wState));
    wstate->memory = state;
    wstate->hash = xcrc32((unsigned char *)state, sizeof(struct el) * (vars_count + proc_count), 0xffffffff);
    return wstate;
}

// Compare deux éléments de la hashtable
int cmp_wstate(wState *state1, wState *state2)
{
    return memcmp(state1->memory, state2->memory, sizeof(struct el) * (vars_count + proc_count));
}

/****************************************************************************/
/*                    Exploration des états atteignables                    */
/****************************************************************************/

// Evaluation d'une expression
int eval(program_state state, expr *e, int else_value)
{
    switch (e->type)
    {
    case OR:
        return eval(state, e->left, else_value) || eval(state, e->right, else_value);
    case AND:
        return eval(state, e->left, else_value) && eval(state, e->right, else_value);
    case EQUAL:
        return eval(state, e->left, else_value) == eval(state, e->right, else_value);
    case NOT:
        return !eval(state, e->left, else_value);
    case ADD:
        return eval(state, e->left, else_value) + eval(state, e->right, else_value);
    case SUB:
        return eval(state, e->left, else_value) - eval(state, e->right, else_value);
    case MUL:
        return eval(state, e->left, else_value) * eval(state, e->right, else_value);
    case GT:
        return eval(state, e->left, else_value) > eval(state, e->right, else_value);
    case LT:
        return eval(state, e->left, else_value) < eval(state, e->right, else_value);
    case ELSE:
        return else_value;
    case INT:
        return e->var;
    case 0:
        return get_val(state, e->var);
    }
}

// Evalue toutes les spécifications pour l'état state et valide celles qui sont vérifiées dans l'état state
void valid_specs(program_state state)
{
    speclist *s = program_specs;
    while (s != NULL)
    {
        s->valid = s->valid || eval(state, s->expr, 0);
        s = s->next;
    }
}

// Sauvegarde l'état state dans la hashtable
// Renvoie 1 si l'état n'était pas déjà dans la hashtable, 0 sinon
int save_state(program_state state)
{
    wState *wstate = make_wstate(state);
    if (wHashFind(hash, wstate) != NULL) return 0;

    wHashInsert(hash, wstate);
    valid_specs(state);

    return 1;
}


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

int *mod_else_values(int *arr, int proc, int s)
{
  int *new_arr = malloc(sizeof(int) * proc_count);
  memcpy(new_arr, arr, sizeof(int) * proc_count);
  new_arr[proc] = s;
  return new_arr;
}

// exec(state, nexts, stacks, guard_visited) va parcourir tout les états atteignable non visités depuis state avec comme prochains stmts nexts et comme environnements DO stacks
// else_values n'a de sens que dans un guard qui indique si un guard a été visité ou non (pour gérer le guard else si il existe)
void exec(program_state state, stmt **nexts, do_stack **stacks, int *else_values)
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
              program_state mod_state = set_val(state, current_stmt->var, eval(state, current_stmt->expr, else_values[proc]));

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
                exec(next_state, new_nexts, stacks, else_values);
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
              exec(next_state, new_nexts, stacks, else_values);
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

              //On reset le else_value
              int *new_else_values = mod_else_values(else_values, proc, 1);

              //On execute l'état
              exec(new_state, new_nexts, new_stacks, new_else_values);
          }
          break;

          // On est dans un IF : on execute les guards
          case IF:
          {
              //On crée le nouvel état
              program_state new_state = set_stmt(state, proc, current_stmt->left);

              //On reset le else_value
              int *new_else_values = mod_else_values(else_values, proc, 1);

              //On execute cet état
              exec(new_state, nexts, stacks, new_else_values);
          }
          break;

          // On est dans un SKIP : on continue juste d'exécuter la suite
          case SKIP:
          {
            if (nexts[proc] == NULL) return;

            //On crée le nouvel état
            program_state new_state = set_stmt(state, proc, nexts[proc]);

            stmt **new_nexts = mod_stmts(nexts, proc, NULL);

            //On execute la suite
            exec(new_state, new_nexts, stacks, else_values);
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
            exec(new_state, new_nexts, new_stacks, else_values);
          }

          //On est dans le cas d'un BREAK : on execute ce qui suit le DO (le DO est suivi d'un SKIP_DO qui s'occupera de dépiler la do_stack)
          case BREAK:
          {
              //On crée le nouvel état
              program_state new_state = set_stmt(state, proc, stacks[proc]->break_s);

              stmt **new_nexts = mod_stmts(nexts, proc, NULL);

              //On execute la suite
              exec(new_state, new_nexts, stacks, else_values);
          }
          break;

          //On est dans le cas d'un GUARD : on regarde si le guard courant est vrai, si oui on l'execute
          //Et on execute les autre guards si il y en a
          case GUARD:
          {
              int guard_state = 1;
              //On regarde si le guard est valide
              if (eval(state, current_stmt->expr, else_values[proc]))
              {
                  guard_state = 0;

                  //Si oui, on crée le nouvel état
                  program_state new_state = set_stmt(state, proc, current_stmt->left);

                  //On execute le guard
                  exec(new_state, nexts, stacks, else_values);
              }


              //On regarde si il y a d'autres guards
              if (current_stmt->right != NULL)
              {
                  //On crée le nouvel état
                  program_state new_state = set_stmt(state, proc, current_stmt->right);

                  //On met à jour else_value
                  int *new_else_values = mod_else_values(else_values, proc, else_values[proc] && guard_state);

                  //On execute les guards
                  exec(new_state, nexts, stacks, new_else_values);
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

    int *else_values = malloc(proc_count * sizeof(int));
    for (int i = 0; i < proc_count; i++) else_values[i] = 1;

    exec(init_state, nexts, stacks, else_values);

    speclist *specs = program_specs;
    int i = 0;
    if (specs == NULL)
        printf("No specs\n");
    while (specs != NULL)
    {
        i++;
        printf("Spec %d: %s\n", i, (specs->valid) ? "Satisfaite" : "Non satisfaite" );
        specs = specs->next;
    }
}
