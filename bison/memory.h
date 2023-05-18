#ifndef MEMORY
#define MEMORY


int get_val(program_state *state, int var);
program_state *set_val(program_state *state, int var, int val);
stmt *get_stmt(program_state *state, int proc);
program_state *set_stmt(program_state *state, int proc, stmt *s);
int save_state(program_state *state); // vérifie les specs + retourne si le state était dans la table de hachage



#endif
