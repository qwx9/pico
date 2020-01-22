#include <u.h>
#include <libc.h>
#include <ctype.h>
#include "dat.h"
#include "fns.h"

Sym *sym;
int nsym;
int Δx, Δy;

static char*
esmprint(char *fmt, ...)
{
	char *p;
	va_list arg;
	
	va_start(arg, fmt);
	p = vsmprint(fmt, arg);
	va_end(arg);
	if(p == nil)
		sysfatal("smprint: %r");
	return p;
}

static char *
estrdup(char *s)
{
	if((s = strdup(s)) == nil)
		sysfatal("estrdup: %r");
	setmalloctag(s, getcallerpc(&s));
	return s;
}

static void *
erealloc(void *p, ulong n)
{
	if((p = realloc(p, n)) == nil)
		sysfatal("realloc: %r");
	setmalloctag(p, getcallerpc(&p));
	return p;
}

static void *
emalloc(ulong n)
{
	void *p;

	if((p = mallocz(n, 1)) == nil)
		sysfatal("emalloc: %r");
	setmalloctag(p, getcallerpc(&n));
	return p;
}

static void
nuketok(void)
{
	char **p;

	for(p=tok; p<tok+ntok; p++)
		free(*p);
	free(tok);
	tok = nil;
	ntok = 0;
}

static char **
newtok(char *s)
{
	char **p;

	tok = erealloc(tok, ++ntok * sizeof *tok);
	p = tok + ntok - 1;
	*p = s;
	return p;
}

static char *
addtok(char *s, int n)
{
	char **p;

	p = newtok(s);
	*p = emalloc(n + 1);
	memcpy(*p, s, n);
	return *p;
}

static Sym *
newsym(char *name)
{
	Sym *s;

	sym = erealloc(sym, ++nsym * sizeof *sym);
	s = sym + nsym - 1;
	s->iname = esmprint("$%zd", s - sym + 1);
	s->cname = esmprint("﹩im[%zd]", s - sym);
	s->name = name == nil ? esmprint("﹩%zd", s - sym + 1) : estrdup(name);
	return s;
}

static Sym *
getsym(char *name, int n)
{
	Sym *s;

	if(n == 0)
		n = strlen(name);
	for(s=sym; s<sym+nsym; s++)
		if(strncmp(s->name, name, n) == 0 && strlen(s->name) == n
		|| strncmp(s->iname, name, n) == 0 && strlen(s->iname) == n)
			return s;
	return nil;
}

static Sym *
addsym(char *name)
{
	Sym *s;

	if((s = getsym(name, 0)) == nil)
		s = newsym(name);
	return s;
}

static void
cleanup(void)
{
	Sym *s;

	nuketok();
	for(s=sym; s<sym+nsym; s++)
		s->ref = 0;
}

static void
fnwrite(int argc, char **argv)
{
	int n, fd, dfd;
	uchar buf[65536];
	Sym *s;

	if(argc != 3){
		fprint(2, "usage: w name path\n");
		return;
	}
	if((s = getsym(argv[1], 0)) == nil){
		fprint(2, "fnwrite: no such image %s\n", argv[1]);
		return;
	}
	if(strcmp(argv[2], s->path) == 0){
		fprint(2, "not overwriting image with itself\n");
		return;
	}
	if((fd = open(s->path, OREAD)) < 0){
		fprint(2, "open: %r\n");
		return;
	}
	if((dfd = create(argv[2], OWRITE, 0666)) < 0){
		fprint(2, "create: %r\n");
		return;
	}
	while((n = read(fd, buf, sizeof buf)) > 0)
		if(write(dfd, buf, n) != n){
			n = -1;
			break;
		}
	close(fd);
	close(dfd);
	if(n < 0)
		fprint(2, "fnwrite: %r\n");
}

static void
fnadd(int argc, char **argv)
{
	char *path;
	Sym *s;

	if(argc < 2 || argc > 3){
		fprint(2, "usage: r name [path]\n");
		return;
	}
	s = addsym(argv[1]);
	path = argc < 3 ? argv[1] : argv[2];
	if(access(path, OREAD) < 0){
		fprint(2, "access %s: %r\n", path);
		return;
	}
	s->path = esmprint("%s%s%s",
		path[0] == '/' ? "" : wdir,
		path[0] == '/' ? "" : "/",
		path);
}

static void
fndisplay(int argc, char **argv)
{
	int i;
	Sym *s;

	if(argc == 1){
		if(nsym > 0)
			show(sym[nsym-1].path);
		return;
	}
	for(i=1; i<argc; i++){
		if((s = getsym(argv[i], 0)) != nil)
			show(s->path);
		else
			fprint(2, "fndisplay: no such image %s\n", argv[i]);
	}
}

static void
fnsize(int argc, char **argv)
{
	char *p;

	if(argc != 3){
		fprint(2, "usage: s width height\n");
		return;
	}
	Δx = strtol(argv[1], &p, 0);
	if(p == argv[1]){
		fprint(2, "fnsize: invalid width\n");
		return;
	}
	Δy = strtol(argv[2], &p, 0);
	if(p == argv[1])
		fprint(2, "fnsize: invalid height\n");
}

static void
fnfiles(int, char **)
{
	Sym *s;

	for(s=sym; s<sym+nsym; s++)
		print("%s %s %s\n", s->iname, s->name, s->path);
}

static int
command(char *p)
{
	struct{
		char *name;
		void (*fn)(int, char**);
	} *cp, cmd[] = {
		"f", fnfiles,
		"s", fnsize,
		"r", fnadd,
		"w", fnwrite,
		"d", fndisplay
	};
	int n;
	char *f[16];

	for(cp=cmd; cp<cmd+nelem(cmd); cp++){
		n = strlen(cp->name);
		if(strncmp(p, cp->name, n) == 0
		&& (p[n] == 0 || isspace(p[n]))){
			n = tokenize(p, f, nelem(f));
			cp->fn(n, f);
			return 1;
		}
	}
	return 0;
}

static int
isbuiltin(char *p, int n)
{
	char **fp, *fn[] = {
		"X", "Y", "Z",
		"x", "y", "z"
	};

	for(fp=fn; fp<fn+nelem(fn); fp++)
		if(strncmp(p, *fp, n) == 0 && strlen(*fp) == n)
			return 1;
	return 0;
}

static int
mkcoords(char *s, char *e)
{
	char *p, **cp, *c[2] = {nil};

	while(isspace(*s))
		s++;
	for(p=s+1, cp=c; p<e; p++){
		if(*p == ']'){
			*p = 0;
			break;
		}else if(*p == ','){
			if(cp >= c + nelem(c)){
				fprint(2, "invalid index spec\n");
				return -1;
			}
			*p = 0;
			*cp++ = p + 1;
		}
	}
	p = esmprint(", %s,%s,%s)", s+1,
		c[0] != nil ? c[0] : "y",
		c[1] != nil ? c[1] : "z");
	newtok(p);
	return 0;
}

static int
getcoords(char *s)
{
	char *p;

	for(p=s; *p!=']' && *p!=0; p++)
		;
	return *p == 0 ? -1 : p + 2 - s;
}

static int
peekrune(char *p, Rune ro)
{
	Rune r;

	while(isspace(*p))
		p++;
	chartorune(&r, p);
	return r == ro;
}

static int
notaword(Rune r)
{
	char *o, *op = "+-*/%?:^,&|<>=![], ()";

	if(isdigitrune(r))
		return 1;
	for(o=op; o<op+strlen(op); o++)
		if(r == *o)
			return 1;
	return 0;
}

static int
getname(char *s)
{
	char *p, *q;
	Rune r;

	q = p = s + chartorune(&r, s);
	while(r != 0 && !notaword(r) && !isspace(r)){
		q = p;
		p += chartorune(&r, p);
	}
	return q - s;
}

void
parse(char *s)
{
	int n, m, nchar;
	char *p, *new;
	Rune r;
	Sym *sp;

	for(p=s, nchar=0, new=nil; *p != 0; p++){
		if(isspace(*p))
			continue;
		if(nchar == 0 && command(p))
			return;
		if(*p == '#')
			break;
		nchar++;
		n = chartorune(&r, p);
		if(notaword(r))
			goto next;
		n = getname(p);
		if(peekrune(p + n, '('))
			goto next;
		if(isbuiltin(p, n))
			goto next;
		if((sp = getsym(p, n)) == nil){
			if(nchar > 1 || !peekrune(p + n, '=')){
				s = emalloc(n + 1);
				memcpy(s, p, n);
				fprint(2, "unknown symbol %s\n", s);
				free(s);
				goto end;
			}
			new = emalloc(n + 1);
			memcpy(new, p, n);
			while(isspace(p[n]))
				n++;
			n++;
			s = p + n;
			goto next;
		}
		addtok(s, p - s);
		sp->ref = 1;
		newtok(estrdup("RIMAGE("));
		newtok(estrdup(sp->cname));
		s = p + n;
		if(!peekrune(s, '[')){
			newtok(estrdup(",x,y,z)"));
			goto next;
		}
		if((m = getcoords(s)) < 0){
			fprint(2, "syntax error: no matching ]\n");
			goto end;
		}
		if(mkcoords(s, s + m - 1) < 0)
			goto end;
		s += m;
		p += m - 1;
	next:
		p += n - 1;
	}
	if(nchar == 0)
		return;
	if(p > s)
		addtok(s, p - s);
	if((p = execute()) != nil){
		sp = newsym(new);
		sp->path = estrdup(p);
		if(!quiet)
			show(p);
	}
end:
	free(new);
	cleanup();
}
