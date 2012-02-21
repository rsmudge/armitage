#
# fix the line formats so windows users can read the files too
#
perl -pi -e 's/\n/\r\n/g' readme.txt
perl -pi -e 's/\n/\r\n/g' whatsnew.txt

