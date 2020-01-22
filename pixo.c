#include <u.h>
#include <libc.h>
#include <ctype.h>
#include <bio.h>
#include "dat.h"
#include "fns.h"

int quiet;

void
main(int argc, char **argv)
{
	char *s;
	Biobuf *bf;

	ARGBEGIN{
	case 'q': quiet = 1; break;
	}ARGEND
	initfiles();
	if((bf = Bfdopen(0, OREAD)) == nil)
		sysfatal("Bfdopen: %r");
	for(;;){
		if(!quiet)
			print("→ ");
		if((s = Brdstr(bf, '\n', 1)) == nil)
			break;
		parse(s);
		free(s);
	}
}
