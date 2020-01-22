typedef struct Sym Sym;

extern char wdir[], pref[];
extern char **tok;
extern int ntok;

struct Sym{
	int ref;
	char *iname;
	char *cname;
	char *name;
	char *path;
};
extern Sym *sym;
extern int nsym;
extern int Δx, Δy;

extern char *prolog, *prepstr, *tailstr;

extern int quiet;
