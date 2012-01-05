#
# Armitage Reporting... (well, sorta... not going to generate PDFs any time soon :))
#

import java.io.*;
import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;

sub dumpTSVData {
	local('$handle $entry $key $value');
	if ($3 is $null) {
		warn("No data for $1");
		return;
	}

	$handle = openf("> $+ $1 $+ .tsv");
	println($handle, join("\t", $2));
	foreach $entry ($3) {
		foreach $key => $value ($entry) {
			$value = strrep(["$value" trim], "\t", "   ", "\n", "\\n");
		}

		println($handle, join("\t", values($entry, $2))); 
	}
	closef($handle);
}

sub dumpXMLData {
	local('$handle $entry $key $value');
	if ($3 is $null) {
		warn("No data for $1");
		return;
	}
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

sub fixVulns {
	local('$id $vuln %vulns %refs $info');
	%refs  = ohash();
	setMissPolicy(%refs, { return @(); });

	# let's group everything by a unique vulnerability id... we're going to collapse the 
	# the vulns into one row with comma separated refs.
	foreach $vuln ($1) {
		$id = $vuln['vid'];
		%vulns[$id] = $vuln;
		push(%refs[$id], $vuln['refs']);
	}

	# fix the references...
	foreach $id => $vuln (%vulns) {
		$vuln['refs'] = join(", ", %refs[$id]); 
		
		if ("exploit/*" iswm $vuln['name'] && substr($vuln['name'], 8) in @exploits) {
			$info = call($mclient, "module.info", "exploit", substr($vuln['name'], 8));

			# fix some options
			$vuln['module'] = $vuln['name'];
			$vuln['name'] = $info['name'];
			$vuln['info'] = replace($info['description'], "\n\\s+", "\n");
		}
		else if ("auxiliary/*" iswm $vuln['name'] && substr($vuln['name'], 10) in @auxiliary) {
			$info = call($mclient, "module.info", "auxiliary", substr($vuln['name'], 10));

			# fix some options
			$vuln['module'] = $vuln['name'];
			$vuln['name'] = $info['name'];
			$vuln['info'] = replace($info['description'], "\n\\s+", "\n");
		}
	}

	return values(%vulns);
}

#
# query all of the data that we want...
# queryData(%workspace)
# 
sub queryData {
	local('%r $progress');	

	# 1. extract the known vulnerability information
	%r['vulns'] = call($mclient, "db.vulns")["vulns"];

	if ($progress) {
		[$progress setProgress: 10];
	}

	%r['vulns'] = fixVulns(%r['vulns']);

	# 2. credentials
	%r['creds'] = call($mclient, "db.creds")["creds"];

	if ($progress) {
		[$progress setProgress: 20];
	}

	# 3. loot
	%r['loots'] = call($mclient, "db.loots")["loots"];

	if ($progress) {
		[$progress setProgress: 30];
	}

	# 4. clients
	%r['clients'] = call($mclient, "db.clients", [new HashMap])["clients"];

	if ($progress) {
		[$progress setProgress: 35];
	}

	# 5. hosts and services
	local('@hosts @services $temp $h $s $x');
	call($mclient, "armitage.prep_export", $1);

	$temp = call($mclient, "armitage.export_data");
	while (size($temp['hosts']) > 0) {
		($h, $s) = values($temp, @('hosts', 'services'));
		addAll(@hosts, $h);
		addAll(@services, $s);
	
		if ($progress) {
			[$progress setProgress: 35 + $x];
		}
		$x += 2;
		sleep(50);
		$temp = call($mclient, "armitage.export_data");
	}

	%r['hosts'] = @hosts;
	%r['services'] = @services;

	return %r;
}

#
# extract and export Metasploit data to easily parsable files (TSV and XML)
#
sub generateArtifacts {
	local('$dialog $select @workspaces $export');

	$dialog = dialog("Export Data", 320, 200);

	@workspaces = map({ return $1['name']; }, workspaces());
	add(@workspaces, "All Hosts");

	$select = select(@workspaces, "Show All");
	$export = [new JButton: "Export"];
	[$export addActionListener: lambda({
		thread(lambda({
			local('$filter $files');
			if ($item eq "All Hosts") {
				$filter = %();
			}
			else {
				$filter = search(workspaces(), 
						lambda({ 
							return iff($1['name'] eq $item, $1); 
						}, \$item));
			}

			$files = _generateArtifacts($filter);
			[gotoFile([new java.io.File: $files])];
		}, $item => [$select getSelectedItem]));
		[$dialog setVisible: 0];
	}, \$select, \$dialog)];

	[$dialog setLayout: [new BorderLayout]];
	[$dialog add: label_for("Workspace:", 100, $select), [BorderLayout CENTER]];
	[$dialog add: center($export), [BorderLayout SOUTH]];
	[$dialog pack];
	[$dialog setVisible: 1];
	[$dialog show];
}

sub _generateArtifacts {
	local('%data $progress');

	$progress = [new javax.swing.ProgressMonitor: $null, "Exporting Data", "Querying Database...", 0, 100]; 
	%data = queryData($1, \$progress);

	[$progress setProgress: 50];
	[$progress setNote: "Exporting Data"];

	# 1. extract the known vulnerability information
	dumpData("vulnerabilities", @("host", "port", "proto", "updated_at", "name", "refs", "info", "module"), %data['vulns']);

	[$progress setProgress: 55];

	# 2. credentials
	dumpData("credentials", @("host", "port", "proto", "sname", "created_at", "active", "ptype", "user", "pass"), %data['creds']);
		
	[$progress setProgress: 60];

	# 3. loot
	dumpData("loots", @("host", "ltype", "created_at", "updated_at", "info", "content_type", "name", "path"), %data['loots']);

	[$progress setProgress: 65];

	# 4. clients
	dumpData("clients", @("host", "created_at", "updated_at", "ua_name", "ua_ver", "ua_string"), %data['clients']);

	[$progress setProgress: 70];

	# 5. hosts
	dumpData("hosts", @("address", "mac", "state", "address", "address6", "name", "purpose", "info", "os_name", "os_flavor", "os_sp", "os_lang", "os_match", "created_at", "updated_at"), %data['hosts']);

	[$progress setProgress: 80];

	# 6. services
	dumpData("services", @("host", "port", "state", "proto", "name", "created_at", "updated_at", "info"), %data['services']);

	[$progress setProgress: 90];

	# 7. take a pretty screenshot of the graph view...
	[$progress setNote: "host picture :)"];

	makeScreenshot("hosts.png");
	if (-exists "hosts.png") {
		logFile("hosts.png", "artifacts", ".");
		deleteFile("hosts.png");
	}

	[$progress setProgress: 100];
	[$progress close];

	return getFileProper(systemProperties()["user.home"], ".armitage", formatDate("yyMMdd"), "artifacts");
}

#
# connects to the database (if necessary), resets the host index for pagination and... rocks it!
#
sub api_prep_export {
	if ($db is $null) {
		$db = connectToDatabase();
	}

	[$db resetHostsIndex];
	[$db execute: "db.filter", $2];
	return %(status => "success");
}

# pages through database and grabs all of the hosts and services data
sub api_export_data {
	local('@hosts $temp @services $stemp');

	# call db.filter here if requested...
	@hosts = call($db, "db.hosts")['hosts'];

	# get all of the services for these hosts...
	[$db resetServicesIndex];
	$temp = call($db, "db.services")['services'];

	while (size($temp) > 0) {
		addAll(@services, $temp);
		[$db nextServicesIndex];
		$temp = call($db, "db.services")['services'];
	}
	
	[$db nextHostsIndex];
	return %(hosts => @hosts, services => @services);
}

sub initReporting {
	global('$poll_lock @events'); # set in the dserver, not in stand-alone Armitage

	wait(fork({
		global('$db');
		[$client addHook: "armitage.export_data", &api_export_data];
		[$client addHook: "armitage.prep_export", &api_prep_export];
	}, \$client, $mclient => $client, \$preferences, \$yaml_file, \$BASE_DIRECTORY, \$yaml_entry));
}
