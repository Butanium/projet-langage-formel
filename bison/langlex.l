%option noyywrap

DIG	[0-9]

%%

"bool"	{ return BOOL; }
"while"	{ return WHILE; }
"break"	{ return BREAK; }
"do"	{ return DO; }
"od"	{ return OD; }
"if"	{ return IF; }
"else"	{ return ELSE; }
"fi"	{ return FI; }
"print"	{ return PRINT; }
"true"	{ return TRUE; }
"false"	{ return FALSE; }
"::" { return GUARD }
"->" { return ARROW }

":="	{ return ASSIGN; }
"^"	{ return XOR; }
"||"	{ return OR; }
"&&"	{ return AND; }
"!"	{ return NOT; }
"==" {return EQUAL; }


[a-z_][a-z0-9_]* { yylval.i = strdup(yytext); return IDENT; }

[	 \n]   { /* ignore */ }

.	{ return *yytext; }

%%

