logo.ssd:
	beebasm -i logotest.s -do logo.ssd -opt 2 -v >out.txt

quicdisc.ssd:
	beebasm -i quicdisc.s -do quicdisc.ssd -v >orig.out.txt

lzsa.ssd:
	beebasm -i lzsatest.s -do lzsa.ssd -v >lzsa.txt
