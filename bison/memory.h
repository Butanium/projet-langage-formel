#ifndef MEMORY
#define MEMORY

typedef struct expr // boolean expression
{
    int type; // INT, OR, AND, NOT, 0 (variable)
    int *var; // VAR index or INT constant
    struct expr *left, *right;
} expr;

typedef struct stmt // command
{
    int type; // ASSIGN, ';', DO, IF, GUARD
    int *var;
    expr *expr;
    struct stmt *left, *right;
} stmt;

typedef struct el* program_state;

int get_val(program_state state, int var);
program_state set_val(program_state state, int var, int val);
stmt get_stmt(program_state state, int proc);
program_state set_stmt(program_state state, int proc, stmt *s);
int save_state(program_state *state); // vérifie les specs + retourne si le state était dans la table de hachage


#endif