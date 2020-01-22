#include <u.h>
#include <libc.h>
#include <plumb.h>
#include "dat.h"
#include "fns.h"

char wdir[1024], pref[64];
char **tok;
int ntok;

static int plumbfd, mkfd;

void
show(char *path)
{
	if(plumbfd < 0)
		return;
	if(plumbsendtext(plumbfd, "pixo", nil, wdir, path) < 0)
		fprint(2, "plumbsendtext: %r\n");
}

static int
system(char *cmd)
{
	int r, argc, pid;
	char name[64], *argv[32];
	Waitmsg *w;

	argc = tokenize(cmd, argv, nelem(argv)-1);
	argv[argc] = nil;
	snprint(name, sizeof name, "/bin/%s", argv[0]);
	switch(pid = fork()){
	case -1:
		fprint(2, "fork: %r\n");
		return -1;
	case 0:
		USED(pid);
		exec(name, argv);
		sysfatal("execl: %r");
	}
	if((w = wait()) == nil){
		fprint(2, "system: lost children\n");
		return -1;
	}
	r = 0;
	if(w->msg != nil && w->msg[0] != 0){
		fprint(2, "system: failure: %s\n", w->msg);
		r = -1;
	}
	free(w);
	return r;
}

char *
execute(void)
{
	int fd;
	char **p, cmd[128];
	Sym *s;
	static char path[128];

	snprint(path, sizeof path, "%s.c", pref);
	if((fd = create(path, OWRITE, 0666)) < 0){
		fprint(2, "create: %r");
		return nil;
	}
	write(fd, prolog, strlen(prolog));
	snprint(path, sizeof path, "%s.%d.bit", pref, nsym + 1);
	fprint(fd,
		"	Memimage **﹩i, *﹩im[%d];\n"
		"	char *out = \"%s\";\n",
		nsym > 0 ? nsym : 1, path);
	for(s=sym; s<sym+nsym; s++)
		if(s->ref)
			fprint(fd, "	﹩im[%zd] = READ(\"%s\");\n",
				s-sym, s->path);
	fprint(fd,
		"	X = %d;\n"
		"	Y = %d;\n",
		Δx, Δy);
	write(fd, prepstr, strlen(prepstr));
	fprint(fd, "		T = ");
	for(p=tok; p<tok+ntok; p++)
		write(fd, *p, strlen(*p));
	write(fd, tailstr, strlen(tailstr));
	close(fd);
	snprint(cmd, sizeof cmd, "mk -f %s.mk %s", pref, pref);
	if(system(cmd) < 0)
		return nil;
	return path;
}

static void
mkfile(void)
{
	char path[64];

	snprint(path, sizeof path, "%s.mk", pref);
	if((mkfd = create(path, OWRITE|ORCLOSE, 0666)) < 0)
		sysfatal("mkfile: %r");
	fprint(mkfd,
		"</$objtype/mkfile\n"
		"%s:Q: %s.c\n"
		"	$CC $CFLAGS -o %s.$O $prereq\n"
		"	$LD -o $target %s.$O\n"
		"	$target\n"
		"	rm -f $target $prereq %s.$O\n",
		pref, pref, pref, pref, pref);
}

void
initfiles(void)
{
	getwd(wdir, sizeof wdir);
	snprint(pref, sizeof pref, "/tmp/pixo.%d", getpid());
	mkfile();
	if((plumbfd = plumbopen("send", OWRITE)) < 0)
		fprint(2, "plumbopen: %r\n");
}
