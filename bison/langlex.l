%option noyywrap

DIG	[0-9]

%%

"var"	{ return VAR; }
"break"	{ return BREAK; }
"do"	{ return DO; }
"od"	{ return OD; }
"if"	{ return IF; }
"else"	{ return ELSE; }
"fi"	{ return FI; }
"reach" { return REACH; }
"proc" { return PROC; }
"end" { return END; }
"skip" {return SKIP;}
"::" { return GUARD; }
"->" { return ARROW; }

":="	{ return ASSIGN; }
"^"	{ return XOR; }
"||"	{ return OR; }
"&&"	{ return AND; }
"!"	{ return NOT; }
"==" {return EQUAL; }
"+" {return ADD;}
"-" {return SUB;}
"*" {return MUL;}
">" {return GT;}
"<" {return LT;}
{DIG}+	{ yylval.n = atoi(yytext); return INT; }

[a-z_][a-z0-9_]* { yylval.i = strdup(yytext); return IDENT; }

"//".*\n { /* ignore */ }

[	 \n]   { /* ignore */ }

.	{ return *yytext; }

%%

