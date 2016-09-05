#!/bin/bash

rm -f SPTK-3.9.tar.gz 2>/dev/null
wget -T 10 -t 3 https://sourceforge.net/projects/sp-tk/files/SPTK/SPTK-3.9/SPTK-3.9.tar.gz
if [ ! -e SPTK-3.9.tar.gz ]; then
	echo "****download of SPTK-3.9.tar.gz failed."
	exit 1
else
	mkdir -p SPTK
	tar -xovzf SPTK-3.9.tar.gz || exit 1
	cd SPTK-3.9
	./configure --prefix=`pwd`/../SPTK || exit 1
	make || exit 1
	make install || exit 1
    cd ..
fi

