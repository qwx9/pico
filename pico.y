%{
#include <u.h>
#include <libc.h>
#include <ctype.h>
#include <bio.h>
#include <draw.h>
#include <event.h>
#include <memdraw.h>

char *newname, *cmd, buf[64*1024], *bufp = buf;

int yylex(void);
int yyparse(void);
void yyerror(char*);

void checkref(char*);
void checkrefn(int);

char *
sym(char *fmt, ...)
{
	va_list args;
	char *s;

	s = bufp;
	va_start(args, fmt);
	bufp = vseprint(s, buf+sizeof buf, fmt, args);
	va_end(args);
	if(bufp >= buf + sizeof(buf) - 1)
		sysfatal("NOPE NOPE NOPE");
	*bufp++ = 0;
	return s;
}

%}

%union
{
	char* s;
	int i;
	double d;
}

%token NAME NEW OLD NUM DBL EOF ERROR
%token <s> FN NAME
%type <s> index zindex newname command expr fileref value
%type <i> NUM
%type <d> DBL

%right '='
%right '?' ':'
%left OR
%left AND
%left '|'
%left '^'
%left '&'
%left EQ NE
%right LSH RSH
%left '<' '>' LE GE
%left '+' '-'
%left '*' '/' '%'
%right POW
%right '!'

%%

start: command EOF { cmd = $1; bufp = buf; return 0; }

index:
	'[' expr ',' expr ',' expr ']'  { $$ = sym("%s,%s,%s", $2, $4, $6); }

zindex:
	index
|	{ $$ = "x,y,z"; }

newname:
	NEW { $$ = "new"; }
|	NEW NAME { $$ = $2; }
|	NAME { $$ = $1; }

command:
	newname zindex '=' expr  
	{ newname = $1; $$ = sym("T = %s; *WIMAGE(%s, %s) = CLIP(T);", $4, $1, $2); }
|	expr
	{ newname = "new"; $$ = sym("T = %s; *WIMAGE(new, x,y,z) = CLIP(T);", $1); }

expr:
	value
|	fileref
|	'x' { $$ = "x"; }
|	'y' { $$ = "y"; }
|	'z' { $$ = "z"; }
|	'X' { $$ = "X"; }
|	'Y' { $$ = "Y"; }
|	'Z' { $$ = "Z"; }
|	"(" expr ")" { $$ = $2; }
|	FN "(" expr ")" { $$ = sym("%s(%s)", $1, $3); }
|	'-' expr %prec '!'  { $$ = sym("-(%s)", $2); }
|	'!' expr { $$ = sym("!(%s)", $2); }
|	expr '+' expr { $$ = sym("(%s)+(%s)", $1, $3); }
|	expr '-' expr { $$ = sym("(%s)-(%s)", $1, $3); }
|	expr '*' expr { $$ = sym("(%s)*(%s)", $1, $3); }
|	expr '/' expr { $$ = sym("DIV(%s, %s)", $1, $3); }
|	expr '%' expr { $$ = sym("MOD(%s, %s)", $1, $3); }
|	expr '<' expr { $$ = sym("(%s) < (%s)", $1, $3); }
|	expr '>' expr { $$ = sym("(%s) > (%s)", $1, $3); }
|	expr LE expr { $$ = sym("(%s) <= (%s)", $1, $3); }
|	expr GE expr { $$ = sym("(%s) >= (%s)", $1, $3); }
|	expr EQ expr { $$ = sym("(%s) == (%s)", $1, $3); }
|	expr NE expr { $$ = sym("(%s) != (%s)", $1, $3); }
|	expr LSH expr { $$ = sym("(%s) << (%s)", $1, $3); }
|	expr RSH expr { $$ = sym("(%s) >> (%s)", $1, $3); }
|	expr '^' expr { $$ = sym("(%s) ^ (%s)", $1, $3); }
|	expr '&' expr { $$ = sym("(%s) & (%s)", $1, $3); }
|	expr '|' expr { $$ = sym("(%s) | (%s)", $1, $3); }
|	expr AND expr { $$ = sym("(%s) && (%s)", $1, $3); }
|	expr OR expr { $$ = sym("(%s) || (%s)", $1, $3); }
|	expr '?' expr ':' expr { $$ = sym("(%s) ? (%s) : (%s)", $1, $3, $5); }
|	expr POW expr { $$ = sym("POW(%s, %s)", $1, $3); }

fileref:
	NAME zindex { checkref($1); $$ = sym("IMAGE(%s, %s)", $1, $2); }
|	"$" NUM zindex { checkrefn($2); $$ = sym("IMAGE(OLD[%d-1], %s)", $2, $3); }
|	OLD zindex { checkrefn(1); $$ = sym("IMAGE(old, %s)", $2); }

value:
	NUM { $$ = sym("%d", $1); }
|	DBL { $$ = sym("%f", $1); }

%%

char *inp;

jmp_buf boomer;

void
kaboom(char *fmt, ...)
{
	va_list arg;
	va_start(arg, fmt);
	vfprint(2, fmt, arg);
	va_end(arg);
	fprint(2, "\n");
	longjmp(boomer, 1);
}

void
yyerror(char *msg)
{
	kaboom("%s", msg);
}

int
isnum(Rune r, char *s, char *p)
{
	if(isdigit(r)
	|| p - s == 1 && (r == 'x' || r == 'X')
	|| p - s > 2 && (s[1] == 'x' || s[1] == 'X') && (r >= 'a' && r <= 'f' || r >= 'A' && r <= 'F'))
		return 1;
	else if(r == '.')
		return 2;
	else
		return 0;
}

int
getnum(Rune r)
{
	int n, x, dbl;
	char s[128], *p;

	for(p=s, n=0, dbl=0; x = isnum(r, s, p); n=chartorune(&r, inp), inp+=n){
		if(p < s+sizeof(s)-1){
			*p++ = (char)r;
			if(x == 2)
				dbl = 1;
		}
	}
	*p = 0;
	inp -= n;
	if(dbl){
		yylval.d = strtod(s, nil);
		return DBL;
	}else{
		yylval.i = strtol(s, nil, 0);
		return NUM;
	}
}

int
getname(Rune r)
{
	int n;
	Rune s[128], *p;

	for(p=s, n=0; isalpharune(r) || isdigitrune(r) || r >= 0x2080 && r <= 0x2089; n=chartorune(&r, inp), inp+=n)
		if(p < s+nelem(s)-1)
			*p++ = r;
	*p = 0;
	inp -= n;
	yylval.s = sym("%S", s);
	if(runestrcmp(s, L"new") == 0)
		return NEW;
	else if(runestrcmp(s, L"log") == 0
	|| runestrcmp(s, L"sin") == 0
	|| runestrcmp(s, L"cos") == 0
	|| runestrcmp(s, L"sqrt") == 0)
		return FN;
	return NAME;
}

int
follow2(Rune r0, Rune r1, int op1, Rune r2, int op2)
{
	int n;
	Rune r;

	if(*inp == 0)
		return 0;
	n = chartorune(&r, inp);
	if(r == r1){
		inp += n;
		return op1;
	}else if(r == r2){
		inp += n;
		return op2;
	}
	return r0;
}

int
follow(Rune r0, Rune rr, int op)
{
	int n;
	Rune r;

	if(*inp == 0)
		return 0;
	n = chartorune(&r, inp);
	if(r == rr){
		inp += n;
		return op;
	}
	return r0;
}

int 
yylex(void)
{
	Rune r;

	for(;;){
		if(*inp == 0)
			return EOF;
		inp += chartorune(&r, inp);
		if(!isspacerune(r))
			break;
	}
	switch(r){
	case '+':
	case '-':
	case '/':
	case '%':
	case '?':
	case ':':
	case '^':
	case '$':
	case '[':
	case ']':
	case ',':
	case '(':
	case ')':
	case 'x':
	case 'X':
	case 'y':
	case 'Y':
	case 'z':
	case 'Z': return r;
	case '&': return follow(r, '&', AND);
	case '|': return follow(r, '|', OR);
	case '*': return follow(r, '*', POW);
	case '<': return follow2(r, '=', LE, '<', LSH);
	case '>': return follow2(r, '=', GE, '>', RSH);
	case '=': return follow(r, '=', EQ);
	case '!': return follow(r, '=', NE);
	}
	if(isdigit(r))
		return getnum(r);
	else if(isalpharune(r))
		return getname(r);
	kaboom("unexpected %C", r);
	return ERROR;
}

int
system(char *s)
{
	int pid;
	
	pid = fork();
	if(pid == 0){
		execl("/bin/rc", "rc", "-c", s, nil);
		_exits(0);
	}
	if(pid == -1){
		fprint(2, "fork: %r\n");
		return -1;
	}
	Waitmsg *w;
	while((w = wait()) != nil && w->pid != pid)
		;
	if(w == nil){
		fprint(2, "%s: wait not found\n", s);
		return -1;
	}
	if(w->msg && w->msg[0]) {
		fprint(2, "%s: failed\n", s);
		free(w);
		return -1;
	}
	free(w);
	return 0;
}

void show(Memimage*);

void
xquit(int, char **)
{
	exits(0);
}

typedef struct File File;
struct File{
	char *name;
	char *path;
	Memimage *m;
	int ref;
	int fd;
};
File *files;
int nfiles;

int DX = 248, DY = 248;

Memimage*
readi(char *name)
{
	int fd;
	Memimage *m, *m1;

	if((fd = open(name, OREAD)) < 0){
		fprint(2, "open %s: %r\n", name);
		return nil;
	}
	m = readmemimage(fd);
	close(fd);
	if(m == nil){
		fprint(2, "readmemimage: %r\n");
		return nil;
	}
	if(m->chan != ABGR32){
		m1 = allocmemimage(m->r, ABGR32);
		memfillcolor(m1, DBlack);
		memimagedraw(m1, m1->r, m, m->r.min, memopaque, ZP, S);
		freememimage(m);
		m = m1;
	}
	return m;
}

int
writei(Memimage *m, char *name, int tmp)
{
	int fd;
	
	if((fd = create(name, OWRITE|(tmp?ORCLOSE:0), 0666)) < 0){
		fprint(2, "create %s: %r\n", name);
		return -1;
	}
	if(writememimage(fd, m) < 0){
		close(fd);
		fprint(2, "writememimage %s: %r\n", name);
		return -1;
	}
	if(tmp)
		return fd;
	close(fd);
	return 0;
}

Memimage*
namei(char *name, int warn)
{
	int i;

	for(i=0; i<nfiles; i++)
		if(strcmp(name, files[i].name) == 0){
			files[i].ref++;
			return files[i].m;
		}
	if(warn)
		fprint(2, "no image %s\n", name);
	return nil;
}

void
iput(char *name, Memimage *m, char *path)
{
	int i;

	for(i=0; i<nfiles; i++)
		if(name[0] && strcmp(name, files[i].name) == 0){
			freememimage(files[i].m);
			files[i].m = m;
			return;
		}
	files = realloc(files, ++nfiles*sizeof files[0]);
	if(strlen(name) == 0)
		files[i].name = smprint("$%d", i+1);
	else
		files[i].name = strdup(name);
	files[i].path = path == nil ? nil : strdup(path);
	files[i].m = m;
	files[i].fd = writei(files[i].m, sym("/tmp/pico-run.%d.bit", i), 1);
	DX = Dx(m->r);
	DY = Dy(m->r);
}

void
checkref(char *name)
{
	if(namei(name, 1) == nil)
		longjmp(boomer, 1);
}

void
checkrefn(int n)
{
	if(n < 1 || n > nfiles)
		kaboom("no image $%d", n);
	files[n-1].ref++;
}

void
xfiles(int argc, char **)
{
	int i;
	if(argc != 1){
		fprint(2, "usage: f\n");
		return;
	}
	for(i=0; i<nfiles; i++)
		print("$%d %s %s %dx%d\n", i+1, files[i].name, files[i].path ? files[i].path : "", Dx(files[i].m->r), Dy(files[i].m->r));
}

void
xread(int argc, char **argv)
{
	Memimage *m;

	if(argc < 2 || argc > 3){
		fprint(2, "usage: r image [filename]\n");
		return;
	}
	m = readi(argc == 3 ? argv[2] : argv[1]);
	if(m != nil)
		iput(argv[1], m, argc == 3 ? argv[2] : argv[1]);
}

void
xwrite(int argc, char **argv)
{
	if(argc < 2 || argc > 3){
		fprint(2, "usage: w image [filename]\n");
		return;
	}
	Memimage *m = namei(argv[1], 1);
	if(m == nil)
		return;
	writei(m, argc == 3 ? argv[2] : argv[1], 0);
}

void
xdisplay(int argc, char **argv)
{
	int i;

	if(argc == 1){
		if(nfiles > 0)
			show(files[nfiles-1].m);
		return;
	}
	
	for(i=1; i<argc; i++){
		Memimage *m = namei(argv[i], 1);
		if(m)
			show(m);
	}
}

char* prolog = 
	"#include <u.h>\n"
	"#include <libc.h>\n"
	"#include <draw.h>\n"
	"#include <memdraw.h>\n"
	"\n"
	"Memimage*\n"
	"READ(char *file)\n"
	"{\n"
	"	Memimage *m;\n"
	"	int fd = open(file, OREAD);\n"
	"	if(fd < 0) sysfatal(\"open %s: %r\", file);\n"
	"	m = readmemimage(fd);\n"
	"	if(m == nil) sysfatal(\"readmemimage %s: %r\", file);\n"
	"	return m;\n"
	"}\n\n"
	"void\n"
	"WRITE(Memimage *m, char *file)\n"
	"{\n"
	"	int fd = create(file, OWRITE, 0666);\n"
	"	if(fd < 0) sysfatal(\"create %s: %r\", file);\n"
	"	if(writememimage(fd, m) < 0) sysfatal(\"writememimage %s: %r\", file);\n"
	"}\n\n"
	"int\n"
	"POW(int a, int b)\n"
	"{\n"
	"	int t;\n"
	"	if(b <= 0) return 1;\n"
	"	if(b == 1) return a;\n"
	"	t = POW(a, b/2);\n"
	"	t *= t;\n"
	"	if(b%2) t *= a;\n"
	"	return t;\n"
	"}\n"
	"\n"
	"int\n"
	"DIV(int a, int b)\n"
	"{\n"
	"	if(b == 0) return 0;\n"
	"	return a/b;\n"
	"}\n"
	"\n"
	"int\n"
	"MOD(int a, int b)\n"
	"{\n"
	"	if(b == 0) return 0;\n"
	"	return a%b;\n"
	"}\n"
	"\n"
	"#define Z 255\n"
	"\n"
	"uchar\n"
	"IMAGE(Memimage *m, int x, int y, int z)\n"
	"{\n"
	"	if(x < 0 || y < 0 || z < 0 || x >= Dx(m->r) || y >= Dy(m->r) || z > 3) return 0;\n"
	"	return byteaddr(m, addpt(m->r.min, Pt(x,y)))[z];\n"
	"}\n"
	"\n"
	"uchar*\n"
	"WIMAGE(Memimage *m, int x, int y, int z)\n"
	"{\n"
	"	static uchar devnull;\n"
	"	if(x < 0 || y < 0 || z < 0 || x >= Dx(m->r) || y >= Dy(m->r) || z > 3) return &devnull;\n"
	"	return byteaddr(m, addpt(m->r.min, Pt(x,y))) + z;\n"
	"}\n"
	"\n"
	"#define CLIP(x) ((x) < 0 ? 0 : (x) > 255 ? 255 : (x))\n"
	"\n"
	"void main(void) {\n"
	"	int x, y, z, T;\n"
	;

int quiet;

void
runprog(char *name, char *cmd)
{
	int i, fd, isnew;
	Memimage *m;

	if((fd = create("/tmp/pico-run.c", OWRITE, 0666)) < 0){
		fprint(2, "create /tmp/pico-run.c: %r");
		return;
	}

	write(fd, prolog, strlen(prolog));
	fprint(fd, "\tint X = %d, Y = %d;\n", DX, DY);
	fprint(fd, "\tMemimage *old, *OLD[%d+1];\n", nfiles);

	isnew = namei(name, 0) == nil;
	if(isnew){
		fprint(fd, "\tMemimage *new = allocmemimage(Rect(0, 0, X, Y), ABGR32);\n");
		fprint(fd, "\tif(new == nil) sysfatal(\"allocmemimage: %%r\");\n");
		if(strcmp(name, "new") != 0)
			fprint(fd, "\tMemimage *%s = new;\n", name);
	}

	for(i=0; i<nfiles; i++){
		if(!files[i].ref)
			continue;
		fprint(fd, "\tOLD[%d] = old = READ(\"/tmp/pico-run.%d.bit\");\n", i, i);
		if(files[i].name[0] != '$'){
			fprint(fd, "\tMemimage *%s = old;\n", files[i].name);
			if(strcmp(files[i].name, name) == 0)
				fprint(fd, "Memimage* new = %s;\n", files[i].name);
		}
	}

	fprint(fd, "\tfor(z=0; z<4; z++) for(y=0; y<Y; y++) for(x=0; x<X; x++) {\n");
	fprint(fd, "\t\t%s\n", cmd);
	fprint(fd, "\t}");
	fprint(fd, "\tWRITE(new, \"/tmp/pico-run.out.bit\");\n");
	fprint(fd, "\texits(0);\n}\n");
	close(fd);

	if(access("/tmp/pico-run.mk", AEXIST) < 0){
		if((fd = create("/tmp/pico-run.mk", OWRITE|ORCLOSE, 0666)) < 0){
			fprint(2, "create /tmp/pico-run.mk: %r");
			goto cleanup;
		}
		fprint(fd, "</$objtype/mkfile\n"
			"/tmp/pico-run:Q: /tmp/pico-run.c\n"
			"\t$CC -o /tmp/pico-run.$O /tmp/pico-run.c\n"
			"\t$LD -o $target /tmp/pico-run.$O\n"
			"\t$target\n"
			"\trm -f /tmp/pico-run.$O\n");
	}
	if(system("mk -f /tmp/pico-run.mk /tmp/pico-run") < 0)
		goto cleanup;

	m = readi("/tmp/pico-run.out.bit");
	if(m){
		if(strcmp(name, "new") != 0)
			iput(name, m, nil);
		else
			iput("", m, nil);
		if(!quiet)
			show(m);
	}

	remove("/tmp/pico-run.c");
cleanup:
	remove("/tmp/pico-run");
	remove("/tmp/pico-run.out.bit");
	for(i=0; i<nfiles; i++)
		files[i].ref = 0;
}

struct {
	char *s;
	void (*f)(int, char**);
} cmds[] = {
	"d", xdisplay,
	"f", xfiles,
	"q", xquit,
	"r", xread,
	"w", xwrite,
};

void
main(int argc, char **argv)
{
	Biobuf b;
	char *p, *f[10];
	int nf;
	int i, l;

	ARGBEGIN{
	case 'q':
		quiet = 1;
		break;
	}ARGEND

	if(memimageinit() < 0)
		sysfatal("memimageinit: %r");
	Binit(&b, 0, OREAD);
	setjmp(boomer);
	for(;;){
	reread:
		if(!quiet)
			fprint(2, "-> ");
		if((p = Brdline(&b, '\n')) == 0)
			break;
		p[Blinelen(&b)-1] = 0;
		while(*p != 0 && isspace(*p))
			p++;
		if(*p == 0)
			goto reread;
		for(i=0; i<nelem(cmds); i++){
			l = strlen(cmds[i].s);
			if(strncmp(p, cmds[i].s, l) == 0 && (p[l] == 0 || isspace(p[l]))){
				nf = tokenize(p, f, nelem(f));
				cmds[i].f(nf, f);
				goto reread;
			}
		}
		
		inp = p;
		newname = nil;
		cmd = nil;
		yyparse();
		runprog(newname, cmd);
	}
	exits(0);	
}

int
newwin(void)
{
	char *srv;
	char spec[100];
	int srvfd, pid;

	rfork(RFNAMEG);

	srv = getenv("wsys");
	if(srv == 0){
		fprint(2, "no graphics: $wsys not set\n");
		return -1;
	}
	srvfd = open(srv, ORDWR);
	free(srv);
	if(srvfd == -1){
		fprint(2, "no graphics: can't open %s: %r\n", srv);
		return -1;
	}

	sprint(spec, "new -dx %d -dy %d -pid 0", DX+8 < 100 ? 100 : DX+8, DY+8 < 48 ? 48 : DY+8);
	if(mount(srvfd, -1, "/mnt/wsys", 0, spec) == -1){
		fprint(2, "no graphics: mount /mnt/wsys: %r (spec=%s)\n", spec);
		return -1;
	}
	close(srvfd);

	switch(pid = rfork(RFFDG|RFPROC|RFNAMEG|RFENVG|RFNOTEG|RFNOWAIT)){
	case -1:
		fprint(2, "no graphics: can't fork: %r\n");
		break;
	}
	if(pid == 0)
		bind("/mnt/wsys", "/dev", MBEFORE);
	else
		unmount(nil, "/mnt/wsys");
	return pid;
}

Image *displayed;

void
eresized(int new)
{
	if(new && getwindow(display, Refnone) < 0)
		fprint(2,"can't reattach to window");
	draw(screen, screen->r, displayed, nil, displayed->r.min);
	flushimage(display, 1);
}

void
showloop(Memimage *m)
{
	Rectangle r;

	if(initdraw(0, 0, "pico") < 0){
		fprint(2, "initdraw: %r\n");
		return;
	}
	einit(Emouse|Ekeyboard);
	if((displayed = allocimage(display, m->r, m->chan, 0, DNofill)) == nil){
		fprint(2, "allocimage: %r\n");
		return;
	}
	r = displayed->r;
	while(r.min.y < displayed->r.max.y){
		r.max.y = r.min.y + 1;
		if(loadimage(displayed, r, byteaddr(m, r.min), Dx(r)*m->depth/8) < 0){
			fprint(2, "loadimage: %r\n");
			return;
		}
		r.min.y++;
	}
	close(0);
	eresized(0);
	for(;;){
		Event e;
		flushimage(display, 0);
		switch(eread(Emouse|Ekeyboard, &e)){
		case Ekeyboard:
			if(e.kbdc == 'q')
				return;
			eresized(0);
			break;
		case Emouse:
			if(e.mouse.buttons&4)
				return;
			break;
		}
	}
}

void
show(Memimage *m)
{
	DX = Dx(m->r);
	DY = Dy(m->r);
	if(newwin() != 0)
		return;
	showloop(m);
	exits(0);
}
