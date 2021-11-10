#
# Logging... yeap, this is very important y0.
#

import java.io.*;

global('%logs');
%logs = ohash();
setMissPolicy(%logs, {
	return [[$cortana getSharedData] getLogger: $2];
});

# logNow("file", "host|all", "text to log");
sub logNow {
	if ([$preferences getProperty: "armitage.log_everything.boolean", "true"] eq "true") {
		local('$today $stream');
		$today = formatDate("yyMMdd");
		$host  = strrep($2, ':', '_');
		mkdir(getFileProper(dataDirectory(), $today, $DESCRIBE, $host));
		$stream = %logs[ getFileProper(dataDirectory(), $today, $DESCRIBE, $host, "$1 $+ .log") ];
		[$stream println: $3];
	}
}

sub logCheck {
	if ([$preferences getProperty: "armitage.log_everything.boolean", "true"] eq "true") {
		local('$today $host');
		$host  = strrep($2, ':', '_');
		$today = formatDate("yyMMdd");
		if ($host ne "") {
			mkdir(getFileProper(dataDirectory(), $today, $DESCRIBE, $host));
			[$1 writeToLog: %logs[ getFileProper(dataDirectory(), $today, $DESCRIBE, $host, "$3 $+ .log") ]];
		}
	}
}

# logFile("filename", "all|host", "type")
sub logFile {
	if ([$preferences getProperty: "armitage.log_everything.boolean", "true"] eq "true") {
		local('$today $handle $data $out $host');
		$host  = strrep($2, ':', '_');
		$today = formatDate("yyMMdd");
		if (-exists $1 && -canread $1) {
			mkdir(getFileProper(dataDirectory(), $today, $DESCRIBE, $host, $3));

			# read in the file
			$handle = openf($1);
			$data = readb($handle, -1);
			closef($handle);

			# write it out.
			$out = getFileProper(dataDirectory(), $today, $DESCRIBE, $host, $3, getFileName($1));
			$handle = openf("> $+ $out");
			writeb($handle, $data);
			closef($handle);
		}
		else {
			print_error("Could not find file: $1");
		}
	}
}

sub initLogSystem {
	[$frame setScreenshotManager: {
		local('$image $title');
		($image, $title) = @_;
		thread(lambda({
			local('$file');
			$title = tr($title, '0-9\W', '0-9_');
			$file = [new java.io.File: getFileProper(formatDate("HH.mm.ss") . " $title $+ .png")];

			[javax.imageio.ImageIO write: $image, "png", $file];
			logFile([$file getAbsolutePath], "screenshots", ".");
			deleteFile([$file getAbsolutePath]);

			showError("Saved " . getFileName($file) . "\nGo to View -> Reporting -> Activity Logs\n\nThe file is in:\n[today's date]/ $+ $DESCRIBE $+ /screenshots");
		}, \$image, \$title));
	}];
}
