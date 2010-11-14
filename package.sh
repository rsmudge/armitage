#!/bin/bash
#
# I know Apache Ant does all of this stuff... I hate working with XML though
# 

rm -f armitage.zip
rm -f armitage.tgz

ant clean
ant compile
cp -r resources/ bin/
cp -r scripts/ bin/
ant jar

#
# build *NIX package
#
mkdir armitage
cp armitage.jar armitage
cp license.txt armitage
cp readme.txt armitage
cp whatsnew.txt armitage
cp -r dist/unix/* armitage

	# kill the silly .svn file
rm -rf armitage/.svn
tar zcvf armitage.tgz armitage

rm -rf armitage

#
# build Windows package
#
mkdir armitage
cp armitage.jar armitage
cp license.txt armitage
cp readme.txt armitage
cp whatsnew.txt armitage
cp -r dist/windows/* armitage

	# kill that silly .svn file
rm -rf armitage/.svn
zip -r armitage.zip armitage

rm -rf armitage

