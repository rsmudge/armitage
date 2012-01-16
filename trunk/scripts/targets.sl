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

global('%hosts $targets');

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

sub sessionPlatform {
	local('$data');
	$data = sessionData($1);
	if ('platform' in $data) {
		return $data['platform'];
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

			if ($host['show'] eq "1") {
				[$graph addNode: $id, describeHost($host), showHost($host), $tooltip];
			}
		}

		# update the routes
		[$graph setRoutes: cast(@routes, ^Route)];

		foreach $highlight (@highlights) {
			[$graph highlightRoute: $highlight[0], $highlight[1]];
		}

		[$graph deleteNodes];
	[$graph end];
}

sub _refreshServices {
	local('$service $host $port');

	# clear all sessions from the hosts
	map({ $1['services'] = %(); }, values(%hosts));

	foreach $service ($1['services']) {
		($host, $port) = values($service, @('host', 'port'));
		%hosts[$host]['services'][$port] = $service;
	}
}

sub refreshServices {
	if ($0 ne "result") { return; }
	_refreshServices(convertAll($3));
	return [$graph isAlive];
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

sub refreshHosts {
	if ($0 ne "result") { return; }

	local('$host $data $address %newh @fixes $key $value');
	$data = convertAll($3);
#	warn("&refreshHosts - $data");

	foreach $host ($data["hosts"]) {
		$address = $host['address'];
		if ($address in %hosts && size(%hosts[$address]) > 1) {
			%newh[$address] = %hosts[$address];
			putAll(%newh[$address], keys($host), values($host));

			if ($host['os_name'] eq "") {
				%newh[$address]['os_name'] = "Unknown";
			}
			else {
				%newh[$address]['os_match'] = join(" ", values($host, @('os_name', 'os_flavor', 'os_sp')));
			}
		}
		else {
			$host['sessions'] = %();
			$host['services'] = %();
			%newh[$address] = $host;

			if ($host['os_name'] eq "" || $host['os_name'] eq "Unknown") {
				$host['os_name'] = "Unknown";
			}
			else {
				%newh[$address]['os_match'] = join(" ", values($host, @('os_name', 'os_flavor', 'os_sp')));
			}
		}

		# we saw this in our hosts, it's ok to show it in the viz.
		%newh[$address]['show'] = 1;
	}

	%hosts = %newh;
	return [$graph isAlive];
}

sub auto_layout_function {
	return lambda({
		[$graph setAutoLayout: $string];
		[$preferences setProperty: "graph.default_layout.layout", $string];
		savePreferences();
	}, $string => $1, $graph => $2);
}

sub graph_items {
	local('$a $b $c');

	$a = menu($1, 'Auto-Layout', 'A');
	item($a, 'Circle', 'C', auto_layout_function('circle', $2));
	item($a, 'Hierarchy', 'C', auto_layout_function('hierarchical', $2));
	item($a, 'Stack', 'C', auto_layout_function('stack', $2));
	separator($a);
	item($a, 'None', 'C', auto_layout_function('', $2));
	
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

sub _importHosts {
	local('$console $success');
	$console = createConsoleTab("Import", 1);
	$success = size($files);
	yield 1024;
	elog("imported hosts from $success file" . iff($success != 1, "s"));
	[$console sendString: "db_import \"" . join(" ", $files) . "\"\n"];
}

# need to pass this function a $command local...
sub importHosts {
	local('$files $thread $closure');
	$files = iff(size(@_) > 0, @($1), chooseFile($multi => 1, $always => 1));
	if ($files is $null || size($files) == 0) {
		return;
	}

	# upload the files please...
	if ($client !is $mclient) {
		$closure = lambda(&_importHosts);
		$thread = [new ArmitageThread: $closure];

		fork({
			local('$file');
			foreach $file ($files) {
				$file = uploadBigFile($file);
			}
			$closure['$files'] = $files;
			[$thread start];
		}, \$mclient, \$files, \$thread, \$closure);
	}
	else {
		thread(lambda(&_importHosts, \$files));
	}
}

# setHostValueFunction(@hosts, varname, value)
#   returns a function that when called will update the metasploit database
sub setHostValueFunction {
	return lambda({
		thread(lambda({
			local('$host %map $key $value');

			while (size(@args) >= 2) {
				($key, $value) = sublist(@args, 0, 2);
				%map[$key] = $value;
				shift(@args);
				shift(@args);
			}

			foreach $host (@hosts) {
				%map['host'] = $host;
				warn(%map);
				call($mclient, "db.report_host", %map);
			}
		}, \@hosts, \@args));
	}, @hosts => $1, @args => sublist(@_, 1));
}

sub clearHostFunction {
	return lambda({
		thread(lambda({
			local('$host @commands $tmp_console');
			foreach $host (@hosts) {
				%hosts[$host] = $null;
			}

			@commands = map({ return "hosts -d $1"; }, @hosts);
			push(@commands, "hosts -h");

			$tmp_console = createConsole($client);
			cmd_all_async($client, $tmp_console, @commands, lambda({
				if ($1 eq "hosts -h") {
					elog("removed " . join(" ", @hosts));
					call($client, "console.destroy", $tmp_console);
				}
			}, \@hosts, \$tmp_console));
		}, \@hosts));
	}, @hosts => $1);
}

sub clearDatabase {
	thread({
		elog("cleared the database");
		call($mclient, "db.clear");
	});
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

sub setDefaultAutoLayout {
	local('$type');
	$type = [$preferences getProperty: "graph.default_layout.layout", "circle"];
	[$1 setAutoLayout: $type];
}

sub makeScreenshot {
	local('$ss');
	
	if ($graph !is $null) {
		$ss = [$graph getScreenshot];

		if ($ss !is $null) {
			[javax.imageio.ImageIO write: $ss, "png", [new java.io.File: getFileProper($1)]];
			return getFileProper($1);
		}
	}
}

sub createDashboard {
	if ($targets !is $null) {
		[$targets actionPerformed: $null];
	}

	local('$graph %hosts $console $split $transfer');

	if ([$preferences getProperty: "armitage.string.target_view", "graph"] eq "graph") {
		setf('&overlay_images', lambda(&overlay_images, $scale => 1.0));
		$graph = [new NetworkGraph: $preferences];
	}
	else {
                setf('&overlay_images', lambda(&overlay_images, $scale => 11.0));
	        $graph = [new NetworkTable: $preferences];
	}

	# setup the drop portion of our drag and drop...
	$transfer = [new ui.ModuleTransferHandler];
	[$transfer setHandler: lambda({
		local('@temp $type $path $host');
		@temp = split('/', $1);
		$type = @temp[0];
		$path = join('/', sublist(@temp, 1));
		$host = [$graph getCellAt: $2];
		if ($host !is $null) {
			moduleAction($type, $path, @($host));
		}
	}, \$graph)];


	setDefaultAutoLayout($graph);

	[$frame setTop: createModuleBrowser($graph, $transfer)];

	$targets = $graph;
	[$targets setTransferHandler: $transfer];

	if ($client !is $mclient) {
		[new ArmitageTimer: $mclient, "db.hosts", 2.5 * 1000L, lambda(&refreshHosts, \$graph), 1];
		[new ArmitageTimer: $mclient, "db.services", 10 * 1000L, lambda(&refreshServices, \$graph), 1];
		[new ArmitageTimer: $mclient, "session.list", 2 * 1000L, lambda(&refreshSessions, \$graph), 1];
	}
	else {
		[new ArmitageTimer: $mclient, "db.hosts", 2.5 * 1000L, lambda(&refreshHosts, \$graph), $null];
		[new ArmitageTimer: $mclient, "db.services", 10 * 1000L, lambda(&refreshServices, \$graph), $null];
		[new ArmitageTimer: $mclient, "session.list", 2 * 1000L, lambda(&refreshSessions, \$graph), $null];
	}

	# this call exists to make sure clients are communicating with the metasploit rpc server
	# before their token expires (they expire after 5 minutes of no activity)
	[new ArmitageTimer: $client, "session.list", 4 * 60 * 1000L, lambda(&refreshSessions, \$graph), $null];

	[$graph setGraphPopup: lambda(&targetPopup, \$graph)];
	[$graph addActionForKeySetting: "graph.save_screenshot.shortcut", "ctrl pressed P", lambda({
		local('$location');
		$location = saveFile2($sel => "hosts.png");
		if ($location !is $null) {
			makeScreenshot($location);
		}
	}, \$graph)];

	let(&makeScreenshot, \$graph);
}
