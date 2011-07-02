#
# Logging... yeap, this is very important y0.
#

import java.io.*;

global('%logs');
%logs = ohash();
setMissPolicy(%logs, {
	return [new PrintStream: [new FileOutputStream: $2, 1], 1, "UTF-8"];
});

sub logCheck {
	if ([$preferences getProperty: "armitage.log_everything.boolean", "true"] eq "true") {
		local('$today');
		$today = formatDate("yyMMdd");
		mkdir(getFileProper(systemProperties()["user.home"], ".armitage", $today, $2));
		[$1 writeToLog: %logs[ getFileProper(systemProperties()["user.home"], ".armitage", $today, $2, "$3 $+ .log") ]];
	}
}

# logFile("filename", "all|host", "type")
sub logFile {
	if ([$preferences getProperty: "armitage.log_everything.boolean", "true"] eq "true") {
		local('$today $handle $data $out');
		$today = formatDate("yyMMdd");
		mkdir(getFileProper(systemProperties()["user.home"], ".armitage", $today, $2, $3));

		# read in the file
		$handle = openf($1);
		$data = readb($handle, -1);
		closef($handle);

		# write it out.
		$out = getFileProper(systemProperties()["user.home"], ".armitage", $today, $2, $3, getFileName($1));
		$handle = openf("> $+ $out");
		writeb($handle, $data);
		closef($handle);
	}
}
