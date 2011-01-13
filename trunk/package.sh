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
cp -r dist/windows/* armitage
cp armitage.jar armitage/msf3/data/armitage
cp readme.txt armitage/readme.armitage.txt
cp whatsnew.txt armitage/whatsnew.armitage.txt

	# kill that silly .svn file
rm -rf armitage/.svn
rm -rf armitage/msf3/.svn
rm -rf armitage/msf3/data/.svn
rm -rf armitage/msf3/data/armitage/.svn
rm -rf armitage/icons/.svn
cd armitage
zip -r ../armitage.zip .
cd ..

rm -rf armitage

#
# update the release directory
#
cd release/
tar zxvf ../armitage.tgz
mv armitage/* armitage-unix
rm -rf armitage

cd ../release/
cd armitage-windows
unzip -o ../../armitage.zip
