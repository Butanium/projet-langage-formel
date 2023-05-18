#ifndef MEMORY
#define MEMORY

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

/* ---- Parsing ---- */
int proc_count;
program_state init_state;
struct varlist *global_vars_names;
struct varlist *current_vars_names;
struct speclist *program_specs;
void add_var(char *s);
void add_proc(stmt *proc);
void make_speclist(expr *exp);
expr *make_expr(int type, int var, expr *left, expr *right);
stmt *make_stmt(int type, int var, expr *expr,
                stmt *left, stmt *right);
int find_ident(char *s);
void make_init_state();

/* ---- Evaluation ---- */
int get_val(program_state state, int var);
program_state set_val(program_state state, int var, int val);
stmt *get_stmt(program_state state, int proc);
program_state set_stmt(program_state state, int proc, stmt *s);
int cmp_wstate(wState *state1, wState *state2);
wState *make_wstate(program_state state);
wHash *hash;

#endif