#
# unzip armitage.tgz in this directory first.
#

mv armitage.jar Armitage.app/Contents/Java
hdiutil create -ov -volname Armitage -srcfolder . armitage.dmg
