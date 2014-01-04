#
# unzip armitage.tgz in this directory first.
#

rm -rf dist
mkdir dist
cp -r Armitage.app dist
cp armitage/armitage.jar dist/Armitage.app/Contents/Java
cp armitage/*.txt dist/
cp *.rtf dist/
rm -rf armitage
mv dist Armitage
hdiutil create -ov -volname Armitage -srcfolder ./Armitage armitage.dmg
rm -rf armitage
