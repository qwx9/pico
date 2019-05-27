</$objtype/mkfile
YFILES=pico.y
OFILES=y.tab.$O
BIN=$home/bin/$objtype
TARG=pico
</sys/src/cmd/mkone

demo:V: doug.pico
	if(! test -f $O.out) mk $O.out || exit
	$O.out -q <doug.pico
