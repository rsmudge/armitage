#
# this code handles the plumbing behind the nifty targets tab... user code can redefine any of these
# functions... so you can use what's here or build your own stuff. 
#

import msf.*;

import armitage.*;
import graph.*;
import table.*;

import javax.swing.*;
import javax.swing.event.*;

import java.awt.*;
import java.awt.event.*;

global('%hosts $targets $FIXONCE');

sub getHostOS {
	return iff($1 in %hosts, %hosts[$1]['os_name'], $null);
}

sub getSessions {
	return iff($1 in %hosts && 'sessions' in %hosts[$1], %hosts[$1]['sessions']);
}

sub sessionToOS {
	return getHostOS(sessionToHost($1));
}

sub sessionData {
	local('$host $data');
	foreach $host => $data (%hosts) {
		if ('sessions' in $data && $1 in $data['sessions']) {
			return $data['sessions'][$1];
		}
	}
	return $null;
}

sub sessionToHost {
	local('$host $data');
	foreach $host => $data (%hosts) {
		if ('sessions' in $data && $1 in $data['sessions']) {
			return $host;
		}
	}
	return $null;
}

sub refreshSessions {
	if ($0 ne "result") { return; }

	local('$address $key $session $data @routes @highlights $highlight $id $host $route $mask');
	$data = convertAll($3);
#	warn("&refreshSessions - $data");

	# clear all sessions from the hosts
	map({ $1['sessions'] = %(); }, values(%hosts));

	foreach $key => $session ($data) {
		$address = $session['target_host'];

		if ($address eq "") {
			$address = split(':', $session['tunnel_peer'])[0];
		}

		if ($address !in %hosts) {
			continue;
		}

		%hosts[$address]['sessions'][$key] = $session;

		# save the highlightable edges
		if ($session['tunnel_local'] ne "") {
			($host) = split(':', $session['tunnel_local']);

			if ('-' isin $host) {
				push(@highlights, @(split('\-', $host)[-1], $address));
			}
			else if ($host eq "Local Pipe") {
				# do something to setup a default pivot highlight
			}
			else {
				push(@highlights, @($host, $address));
			}
		}

		# save the route information related to this meterpreter session
		if ($session['routes'] ne "") {
			foreach $route (split(',', $session['routes'])) {
				($host, $mask) = split('/', $route);
				push(@routes, [new Route: $host, $mask, $address]);
			}
		}
	}

	[SwingUtilities invokeLater: lambda(&refreshGraph, \@routes, \@highlights, \$graph)];

	return [$graph isAlive];
}

sub refreshGraph {
	local('$address $key $session $data $highlight $id $host $route $mask');

	# update everything...
	[$graph start];
		# update the hosts
		foreach $id => $host (%hosts) { 
			local('$tooltip');
			if ('os_match' in $host) {
				$tooltip = $host['os_match'];
			}
			else {
				$tooltip = "I know nothing about $id";
			}

			[$graph addNode: $id, describeHost($host), showHost($host), $tooltip];
		}

		# update the routes
		[$graph setRoutes: cast(@routes, ^Route)];

		foreach $highlight (@highlights) {
			[$graph highlightRoute: $highlight[0], $highlight[1]];
		}

		[$graph deleteNodes];
	[$graph end];
}

sub refreshServices {
	if ($0 ne "result") { return; }

	local('$data $service $host $port');
	$data = convertAll($3);
#	warn("&refreshServices - $data");

	# clear all sessions from the hosts
	map({ $1['services'] = %(); }, values(%hosts));

	foreach $service ($data['services']) {
		($host, $port) = values($service, @('host', 'port'));
		%hosts[$host]['services'][$port] = $service;
	}

	return [$graph isAlive];
}

sub _fixOSInfo {
	local('$note $hosts $info $host');
	($note, $hosts) = @_;
	$host = $note['host'];

	if ($note['type'] eq "host.os.nmap_fingerprint" && $host in %hosts) {
		$info = %hosts[$note['host']];

		if ($host in $hosts) {
			$info['os_name'] = $note['os_family'];
			$info['os_version'] = $note['os_version'];
			call($client, "db.report_host", %(host => $host, os_name => $info['os_name'], os_flavor => $info['os_version']));
			$FIXONCE = 1;
		}
		$info['os_match'] = $note['os_match'];

		return;
	}
	else if ($note['type'] eq "smb.fingerprint" && $host in %hosts) {
		$info = %hosts[$note['host']];

		if ($host in $hosts) {
			$info['os_name'] = $note['os_name'];
			$info['os_version'] = $note['os_flavor'];
			if ($info['os_name'] ne "Unknown") {
				call($client, "db.report_host", %(host => $host, os_name => $info['os_name'], os_flavor => $info['os_version']));
				$FIXONCE = 1;
			}
		}

		if ('os_sp' in $note) {
			$info['os_match'] = $note['os_flavor'] . ", " . $note['os_sp'];
		}
		else {
			$info['os_match'] = $note['os_flavor'];
		}

		return;
	}
}

sub quickParse {
	if ($1 ismatch '.*? host=(.*?)(?:\s*service=.*?){0,1}\s*type=(.*?)\s+data=\\{(.*?)\\}') {
		local('$host $type $data %r $key $value');
		($host, $type, $data) = matched();
		%r = %(host => $host, type => $type);
		while ($data hasmatch ':([a-z_]+)\=\>"([^"]+)"') {
			($key, $value) = matched();
			%r[$key] = $value;
		}
		return %r;
	}
}

sub fixOSInfo {
	# let's try using sysinfo as well
	local('$host $sessions $hosts $sid $session $flag $os');
	$hosts = copy($1);

	foreach $host ($hosts) {
		$sessions = getSessions($host);
		$os = getHostOS($host);
		if (size($sessions) > 0) {	
			warn("Going to do sysinfo for $host ( $+ $os $+ )");
			$flag = $null;
			foreach $sid => $session ($sessions) {
				if ($session['type'] eq "meterpreter" && $flag is $null) {
					$flag = 1;
					dispatchEvent(lambda({ 
						m_cmd($sid, "sysinfo");
					}, \$sid));
				}
			}
	
			iff($flag, remove());
		}
	}

	# db.notes MSF call keeps locking up... *sigh*
	local('$tmp_console');
	$tmp_console = createConsole($client);
	cmd($client, $tmp_console, "db_notes", lambda({
		local('$line $r');
		foreach $line (split("\n", $3)) {
			$r = quickParse($line);
			if ($r) {
				_fixOSInfo($r, $hosts);				
			}
		}
		call($client, "console.destroy", $tmp_console);
	}, \$hosts, \$tmp_console));
}

sub refreshHosts {
	if ($0 ne "result") { return; }

	local('$host $data $address %newh @fixes $key $value');
	$data = convertAll($3);
#	warn("&refreshHosts - $data");

	foreach $host ($data["hosts"]) {
		$address = $host['address'];
		if ($address in %hosts && size(%hosts[$address]) > 1) {
			# let's not overwrite already known values with incomplete values.
			foreach $key => $value ($host) {
				if ($value eq "") {
					remove();
				}
			}
			%newh[$address] = %hosts[$address];
			putAll(%newh[$address], keys($host), values($host));

			if ($host['os_name'] eq "") {
				push(@fixes, $address);
				%newh[$address]['os_name'] = "Unknown";
			}
			# we're doing this because Metasploit's new host normalization does not populate the os_flavor field
			# AND it overwrites ours by clearing it out.... blah!
			else if ("*Windows*" iswm $host['os_name'] && $host['os_flavor'] eq "") {
				push(@fixes, $address);
			}
		}
		else {
			$host['sessions'] = %();
			$host['services'] = %();
			%newh[$address] = $host;

			if ($host['os_name'] eq "" || $host['os_name'] eq "Unknown") {
				$host['os_name'] = "Unknown";
				push(@fixes, $address);
			}
		}
	}

	%hosts = %newh;

	# lock this host resolving nonsense so X hosts are not bombarding
	# one poor meterpreter session
        if ($client !is $mclient && ($FIXONCE is $null || size(@fixes) > 0)) {
                local('%r');
		%r = call($mclient, "armitage.lock", "sessions");
		if (%r["error"]) {
			warn(%r["error"] . " - not resolving OS info (this is OK--FYI)");
		}
		else {
			if ($FIXONCE is $null && size(%hosts) > 0) {
				fixOSInfo(keys(%hosts));
			}
			else if (size(@fixes) > 0) {
				fixOSInfo(@fixes);
			}

			# lock this var for 3 seconds. That should be enough time for the database to update
			# with the changes made to the host information for these boxes
			thread({
				call($mclient, "armitage.refresh");
				yield 3000;
				call($mclient, "armitage.unlock", "sessions");
			});
		}
	}
	else if ($client is $mclient) {
		if ($FIXONCE is $null && size(%hosts) > 0) {
			fixOSInfo(keys(%hosts));
		}
		else if (size(@fixes) > 0) {
			fixOSInfo(@fixes);
		}
	}

	return [$graph isAlive];
}

sub graph_items {
	local('$a $b $c');

	$a = menu($1, 'Auto-Layout', 'A');
	item($a, 'Circle', 'C', lambda({ [$graph setAutoLayout: 'circle']; }, $graph => $2));
	item($a, 'Hierarchy', 'C', lambda({ [$graph setAutoLayout: 'hierarchical']; }, $graph => $2));
	item($a, 'Stack', 'C', lambda({ [$graph setAutoLayout: 'stack']; }, $graph => $2));
	separator($a);
	item($a, 'None', 'C', lambda({ [$graph setAutoLayout: $null]; }, $graph => $2));
	
	$b = menu($1, 'Layout', 'L');
	item($b, 'Circle', 'C', lambda({ [$graph doCircleLayout]; }, $graph => $2));
	item($b, 'Hierarchy', 'C', lambda({ [$graph doHierarchicalLayout]; }, $graph => $2));
	item($b, 'Stack', 'C', lambda({ [$graph doStackLayout]; }, $graph => $2));

	$c = menu($1, 'Zoom', 'Z');
	item($c, 'In', 'I', lambda({ [$graph zoom: 0.25]; }, $graph => $2));
	item($c, 'Out', 'O', lambda({ [$graph zoom: -0.25]; }, $graph => $2));
	separator($c);
	item($c, 'Reset', 'I', lambda({ [$graph resetZoom]; }, $graph => $2));
}

# need to pass this function a $command local...
sub importHosts {
	local('$files');
	$files = iff(size(@_) > 0, @($1), chooseFile($multi => 1, $always => 1));

	thread(lambda({
		local('$file $handle $data $result $name $success');
		foreach $file ($files) {
			$handle = openf($file);
			$data   = [Base64 encode: readb($handle, -1)];
			closef($handle);

			$name = getFileName($file);
	
			$result = call($client, "db. $+ $command", %(data => $data));

			if ($result is $null || $result['result'] != "success") {
				showError("Import $name failed:\n $+ $result");
			}
			else {
				$success++;
			}
		}

		if ($success > 0) {
			fork({ showError("Imported $success file" . iff($success != 1, "s")); }, \$frame, \$success);
			refreshTargets();
		}
	}, \$files, \$command));
}

# setHostValueFunction(@hosts, varname, value)
#   returns a function that when called will update the metasploit database
sub setHostValueFunction {
	return lambda({
		local('$host %map $key $value');

		while (size(@args) >= 2) {
			($key, $value) = sublist(@args, 0, 2);
			%map[$key] = $value;
			shift(@args);
			shift(@args);
		}

		foreach $host (@hosts) {
			%map['host'] = $host;
			call($client, "db.report_host", %map);
		}

		refreshTargets();
	}, @hosts => $1, @args => sublist(@_, 1));
}

sub clearHostFunction {
	return lambda({
		local('$host');
		foreach $host (@hosts) {
			call($client, "db.del_host", %(address => $host));
			%hosts[$host] = $null;
		}
		$FIXONCE = $null;
		refreshTargets();
	}, @hosts => $1);
}

sub clearHosts {
	local('@hosts $r $host');

	$r = call($client, "db.hosts", %());
	@hosts = map({ return $1["address"]; }, $r["hosts"]);
	foreach $host (@hosts) {
		call($client, "db.del_host", %(address => $host));
	}
	%hosts = %();
	$FIXONCE = $null;
	refreshTargets();
	elog("cleared all hosts");
}

# called when a target is clicked on...
sub targetPopup {
        local('$popup');
        $popup = [new JPopupMenu];

        # no hosts are selected, create a menu related to the graph itself
        if (size($1) == 0 && [$preferences getProperty: "armitage.string.target_view", "graph"] eq "graph") {
		graph_items($popup, $graph);
		[$popup show: [$2 getSource], [$2 getX], [$2 getY]];
        }
        else if (size($1) > 0) {
		host_selected_items($popup, $1);
		[$popup show: [$2 getSource], [$2 getX], [$2 getY]];
        }
}

sub refreshTargets {
	warn("refreshTargets was called");

	if ($client !is $mclient && $mclient !is $null) {
		call($mclient, "armitage.refresh");
	}

	[new ArmitageTimer: $mclient, "db.hosts", @([new HashMap]), 0L, lambda(&refreshHosts, $graph => $targets)];
	[new ArmitageTimer: $mclient, "db.services", @([new HashMap]), 0L, lambda(&refreshServices, $graph => $targets)];
	[new ArmitageTimer: $mclient, "session.list", $null, 0L, lambda(&refreshSessions, $graph => $targets)];
}

sub createTargetTab {
	local('$graph %hosts');

        $graph = [new NetworkGraph: $preferences];
	setDefaultAutoLayout($graph);

	[$frame addTab: "Targets", $graph, $graph];

	[new ArmitageTimer: $mclient, "db.hosts", @([new HashMap]), 10 * 1000L, lambda(&refreshHosts, \$graph)];
	[new ArmitageTimer: $mclient, "db.services", @([new HashMap]), 15 * 1000L, lambda(&refreshServices, \$graph)];
	[new ArmitageTimer: $mclient, "session.list", $null, 5 * 1000L, lambda(&refreshSessions, \$graph)];

	[$graph setGraphPopup: lambda(&targetPopup, \$graph)];
}

sub setDefaultAutoLayout {
	local('$type');
	$type = [$preferences getProperty: "graph.default_layout.layout", "circle"];
	[$1 setAutoLayout: $type];
}

sub createDashboard {
	if ($targets !is $null) {
		[$targets actionPerformed: $null];
	}

	local('$graph %hosts $console $split');

	if ([$preferences getProperty: "armitage.string.target_view", "graph"] eq "graph") {
                setf('&overlay_images', lambda(&overlay_images, $scale => 1.0));
	        $graph = [new NetworkGraph: $preferences];
	}
	else {
                setf('&overlay_images', lambda(&overlay_images, $scale => 11.0));
	        $graph = [new NetworkTable: $preferences];
	}
	setDefaultAutoLayout($graph);

	[$frame setTop: createModuleBrowser($graph)];

	$targets = $graph;

	[new ArmitageTimer: $mclient, "db.hosts", @([new HashMap]), 10 * 1000L, lambda(&refreshHosts, \$graph)];
	[new ArmitageTimer: $mclient, "db.services", @([new HashMap]), 15 * 1000L, lambda(&refreshServices, \$graph)];
	[new ArmitageTimer: $mclient, "session.list", $null, 5 * 1000L, lambda(&refreshSessions, \$graph)];

	[$graph setGraphPopup: lambda(&targetPopup, \$graph)];
	[$graph addActionForKeySetting: "graph.refresh_targets.shortcut", "ctrl pressed R", {
		$FIXONCE = $null;
		%hosts = %();
		refreshTargets();
	}];
	[$graph addActionForKeySetting: "graph.save_screenshot.shortcut", "ctrl pressed P", lambda({
		local('$location');
		$location = saveFile2($sel => "hosts.png");
		if ($location !is $null) {
			[javax.imageio.ImageIO write: [$graph getScreenshot], "png", [new java.io.File: $location]];
		}
	}, \$graph)];
}
