#
# Logging... yeap, this is very important y0.
#

import java.io.*;

global('%logs');
%logs = ohash();
setMissPolicy(%logs, {
	return [new PrintStream: [new FileOutputStream: $2, 1], 1, "UTF-8"];
});

# logNow("file", "host|all", "text to log");
sub logNow {
	if ([$preferences getProperty: "armitage.log_everything.boolean", "true"] eq "true") {
		local('$today $stream');
		$today = formatDate("yyMMdd");
		mkdir(getFileProper(systemProperties()["user.home"], ".armitage", $today, $2));
		$stream = %logs[ getFileProper(systemProperties()["user.home"], ".armitage", $today, $2, "$1 $+ .log") ];
		[$stream println: $3];
	}
}

sub logCheck {
	if ([$preferences getProperty: "armitage.log_everything.boolean", "true"] eq "true") {
		local('$today');
		$today = formatDate("yyMMdd");
		if ($2 ne "") {
			mkdir(getFileProper(systemProperties()["user.home"], ".armitage", $today, $2));
			[$1 writeToLog: %logs[ getFileProper(systemProperties()["user.home"], ".armitage", $today, $2, "$3 $+ .log") ]];
		}
	}
}

# logFile("filename", "all|host", "type")
sub logFile {
	if ([$preferences getProperty: "armitage.log_everything.boolean", "true"] eq "true") {
		local('$today $handle $data $out');
		$today = formatDate("yyMMdd");
		if (-exists $1 && -canread $1) {
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
		else {
			warn("Could not find file: $1");
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

			showError("Saved $file $+ \nGo to View -> Reporting -> Activity Logs\n\nThe file is in:\n[today's date]/screenshots");
		}, \$image, \$title));
	}];
}

sub dumpTSVData {
	local('$handle $entry');
	$handle = openf("> $+ $1 $+ .tsv");
	println($handle, join("\t", $2));
	foreach $entry ($3) {
		println($handle, join("\t", values($entry, $2))); 
	}
	closef($handle);
}

sub dumpXMLData {
	local('$handle $entry $key $value');
	$handle = openf("> $+ $1 $+ .xml");
	println($handle, "< $+ $1 $+ >");
	foreach $entry ($3) {
		println($handle, "\t<entry>");
		foreach $key ($2) {
			$value = $entry[$key];
			if ($key eq "info") {
				println($handle, "\t\t< $+ $key $+ ><![CDATA[ $+ $value $+ ]]></ $+ $key $+ >");
			}	
			else {
				println($handle, "\t\t< $+ $key $+ > $+ $value $+ </ $+ $key $+ >");
			}
		}
		println($handle, "\t</entry>");
	}
	println($handle, "</ $+ $1 $+ >");
	closef($handle);
}

sub dumpData {
	dumpTSVData($1, $2, $3);
	dumpXMLData($1, $2, $3);
	logFile("$1 $+ .tsv", "artifacts", "tsv");
	logFile("$1 $+ .xml", "artifacts", "xml");
	deleteFile("$1 $+ .tsv");
	deleteFile("$1 $+ .xml");
}

#
# extract and export Metasploit data to easily parsable files (TSV and XML)
#
sub generateArtifacts {
	local('@data $d $progress');

	$progress = [new javax.swing.ProgressMonitor: $null, "Exporting Data", "vulnerabilities", 0, 100]; 

	# 1. extract the known vulnerability information
	@data = call($client, "db.vulns", [new HashMap])["vulns"];
	dumpData("vulnerabilities", @("host", "port", "proto", "time", "name", "refs"), @data);

	[$progress setProgress: 15];
	[$progress setNote: "credentials"];

	# 2. credentials
	@data = call($client, "db.creds", [new HashMap])["creds"];
	dumpData("credentials", @("host", "port", "proto", "sname", "time", "active", "type", "user", "pass"), @data);
		
	[$progress setProgress: 30];
	[$progress setNote: "loot"];

	# 3. loot
	@data = call($client, "db.loots")["loots"];
	dumpData("loots", @("host", "ltype", "created_at", "updated_at", "info", "content_type", "name", "path"), @data);

	[$progress setProgress: 45];
	[$progress setNote: "clients"];

	# 4. clients
	@data = call($client, "db.clients", [new HashMap])["clients"];
	dumpData("clients", @("host", "created_at", "updated_at", "ua_name", "ua_ver", "ua_string"), @data);

	# 5. notes
		# db.notes is currently broken, need to patch it first before I can export it here.

	# 6. hosts and services
	local('@services @hosts $host $value $key $service');

	foreach $host => $value (%hosts) {
		push(@hosts, $value);
		if ('services' in $value) {
			foreach $key => $service ($value['services']) {
				push(@services, $service);
			}
		}
	}

	[$progress setProgress: 60];
	[$progress setNote: "hosts"];

	dumpData("hosts", @("address", "mac", "state", "address", "address6", "name", "purpose", "info", "os_name", "os_flavor", "os_sp", "os_lang", "os_match", "created_at", "updated_at"), @hosts);

	[$progress setProgress: 75];
	[$progress setNote: "services"];

	dumpData("services", @("host", "port", "state", "proto", "name", "created_at", "updated_at", "info"), @services);

	[$progress setProgress: 90];
	[$progress setNote: "host picture :)"];

	# 7. take a pretty screenshot of the graph view...
	makeScreenshot("hosts.png");
	if (-exists "hosts.png") {
		logFile("hosts.png", "artifacts", ".");
		deleteFile("hosts.png");
	}

	[$progress setProgress: 100];
	[$progress close];

	return getFileProper(systemProperties()["user.home"], ".armitage", formatDate("yyMMdd"), "artifacts");
}
